import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'package:tablet_chords_dart/classes/models.dart';
import 'package:tablet_chords_dart/clients/opensong_dav_client.dart';
import 'package:tablet_chords_dart/clients/pco_client.dart';
import 'package:tablet_chords_dart/handlers/routes.dart';
import 'package:tablet_chords_dart/ws/wsmanager.dart';
import 'package:tablet_chords_dart/ws/wsmessage.dart';

import '../conf/conf.dart' as config;

extension LeftPad on int {
  String pad(int num) => toString().padLeft(num, '0');
}

Response respondJsonOK(Object obj) {
  return Response.ok(json.encode(obj), headers: {'Content-Type': 'application/json'});
}

// GLOBALS

// in-memory caches
final songsByPath = <String, Song>{};
final setsByPath = <String, Setlist>{};
final setsCache = <Setlist>[];

// blacklist
const blacklist = {};

// clients for remote data
late SongsSetsClient songsSetsClient;

// the manager for websocket connections
late WebSocketManager wsManager;

Timer? primeSetlistTimer;

// define the API
var setPathParam = DescribedParam(
  'path',
  'string',
  'With OpenSong, refers to file in the Sets subdirectory. With PlanningCenter, refers to a plan ID. May also be one of the following options.',
  options: [
    DescribedOption('--today--', 'sets the path to YYYY-MM-DD for today'),
    DescribedOption('--latest--', 'loads the latest set'),
  ],
);
var setQueryParams = [
  DescribedParam('filter', 'string', 'filter the songs, use comma to apply multiple filters (applied in order)',
      options: [
        DescribedOption('pre-alternates', 'if set, includes songs until a song with ALTERNATES in the title'),
        DescribedOption('no-duplicates', 'excludes duplicate songs'),
        DescribedOption('no-lyrics', 'excludes lyrics from all songs'),
        DescribedOption('no-chords', 'excludes chord lines from songs'),
        DescribedOption('ccli-only', 'includes only songs with ccli numbers'),
      ]),
  DescribedParam(
    'title',
    'string',
    'includes / excludes sets where the title contains text (case insensitive) (prefix with ! to exclude)',
  ),
];
List<DescribedRoute> apiRoutes = [
  DescribedRoute(
    '/Sets/',
    'serves a list of recent Setlists',
    setsHandler,
    queryParams: setQueryParams,
  ),
  DescribedRoute(
      '/Sets/<path>',
      'serves data for Setlist identified by path. Note, there are two special names available, --today-- and --latest--.',
      setsHandler,
      routeParams: [setPathParam],
      queryParams: setQueryParams),
  // DescribedRoute('/Songs/', 'serves a list of all available songs', songsHandler),
  // DescribedRoute('/Songs/<dir>/<song>', 'serves an individual song', songsHandler),
  DescribedRoute('/alert', 'Sends an alert message to connected tablets', alertsHandler),
  DescribedRoute('/refresh', 'refreshes the internal setlist cache', (req) {
    primeSetlistCache();
    return respondJsonOK(WebSocketMessage('info', {'text': 'refreshing'}));
  }),
];
List<DescribedRoute> staticRoutes = [
  DescribedRoute('/', 'Root route. Serves index.html', rootHandler),
  DescribedRoute(
    '/help',
    'Help route. Serves the contents of the `help` String variable',
    (req) => Response.ok(help(), headers: {'content-type': 'text/plain'}),
  ),
  DescribedRoute('/<filename>', 'serves hosted js, css, and image files', staticHandler),
  DescribedRoute('/public/<filename>', 'DEPRECATED: serves hosted js, css, and image files', staticHandler),
];

// Configure documentation.
String help() {
  var staticHelp = staticRoutes.map((route) => route.toString()).join('\n');
  var apiHelp = apiRoutes.map((route) => route.toString()).join('\n');
  return '''
STATIC FILE ROUTES

$staticHelp

API DOCUMENTATION

$apiHelp

WEBSOCKET COMMANDS:
{type: 'alert', data: {text: 'ALERT_TEXT'}}  => will display an alert on every connected tablet
{type: 'control', data: {set: 'SETNAME'}}  `=> will request control of a setlist
{type: 'key', data: {set: 'SETNAME', songnum: SONGNUM, key: 'KEY'}}  => will send a key update notification

OLD API DOCUMENTATION

/ or /index.html  => serve index.html
/FILE             => serves static files from the public subdirectory
/Sets/            => serves list of Setlists
/Sets/NAME        => serves data for Setlist identified by NAME
/Sets/--today--   => will replace --today-- with today's date YYYY-MM-DD before making request
/Sets/--latest--  => will serve the most recent setlist (see implementation below for notes on caching)
/Songs/           => serves list of Songs (DO NOT USE, NOT CACHED, SO WILL BE SLOOOOOOW!)
/alert            => sends a message specified by query param `msg` to all clients
/refresh          => asks the server to reprime the setlist cache

QUERY VARIABLES
?filter=a,b,...  => will filter the results, multiple filters with comma (applied in order)

SONG FILTERS:
pre-alternates   => ignores all songs following a song with ALTERNATES in the title
no-duplicates    => includes only the first instance of a song in a setlist (based on title)
no-lyrics        => strips lyrics data from songs before returning
no-chords        => strips chords from songs before returning
ccli-only        => ignores all songs without ccli data

SET FILTERS:
text             => includes sets where the title contains text (case insensitive)
!text            => excludes sets where the title contains text (case insensitive)

''';
}

Router setupRoutes(String prefix) {
  final router = Router();
  for (var routelist in [staticRoutes, apiRoutes]) {
    for (var r in routelist) {
      var path = '$prefix${r.path}';
      print('setting up route for $path');
      router.get(path, r.handler);
    }
  }
  return router;
}

// HANDLERS

// alert handler
FutureOr<Response> alertsHandler(Request req) async {
  String msg = req.url.queryParameters['msg'] ?? '';
  var wm = WebSocketMessage.alert(msg);
  wsManager.broadcast(wm);
  return respondJsonOK(wm);
}

// static handler
FutureOr<Response> staticHandlerHelper(File f, {Uint8List Function(Uint8List)? postProcess}) async {
  final mimeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'js': 'text/javascript',
    'json': 'application/json',
    'html': 'text/html',
  };
  if (await f.exists()) {
    var bytes = await f.readAsBytes();
    if (postProcess != null) bytes = postProcess(bytes);
    var fdata = f.path.split('.');
    var ext = 'txt';
    if (fdata.length > 1) {
      ext = fdata.last;
    }
    var mime = mimeMap[ext] ?? 'text/plain';
    return Response.ok(bytes, headers: {'Content-Type': mime});
  }
  return Response.notFound('${f.path} not found');
}

FutureOr<Response> staticHandler(Request req) async {
  // remove the subdirectory (leading slashes are not included in url.path)
  // String localPath = req.url.path.replaceFirst('${config.serverDirectory}/', '');
  String localPath = req.params['filename']!;
  if (localPath.startsWith('/public/')) {
    localPath = localPath.replaceAll(RegExp(r'/?public/?'), '');
  }
  var f = File('public/$localPath');
  return staticHandlerHelper(f);
}

/// serves a single set (if path is sent) or a list of all upcoming setlists
FutureOr<Response> setsHandler(Request req) async {
  var setPath = req.params['path'];

  // if we are using dav, then we only want the path after the davDir

  // setPath is set when a single setlist is requested
  if (setPath != null) {
    setPath = Uri.decodeComponent(setPath);

    // handle special case setlist names
    if (setPath == '--latest--') {
      if (setsByPath.isEmpty) {
        await primeSetlistCache();
      }
      if (setsByPath.isEmpty) {
        setPath = '--today--';
      }

      // look up the latest setPath by doing a "reduce" method
      // you could also do this by sorting first and then popping the first/last item
      // but I wanted to learn reduce
      setPath = setsByPath.values.reduce((value, element) => value.date.isAfter(element.date) ? value : element).path;
    }

    // create a set path from today's date and attempt to load it
    if (setPath == '--today--') {
      var now = DateTime.now();
      setPath = '${now.year.pad(4)}-${now.month.pad(2)}-${now.day.pad(2)}';
    }

    // get a single setlist
    Setlist? set = await songsSetsClient.getSetlist(setPath, withSongs: true);
    if (set == null) {
      return Response.notFound('SETLIST NOT FOUND: $setPath could not be found');
    }

    if (set.songs.isEmpty) {
      return Response.notFound('SETLIST $setPath CONTAINS NO SONGS');
    }

    // cache this result for later
    setsByPath[set.path] = set;

    // cache the songs for later
    for (var song in set.songs) {
      songsByPath[song.path] = song;
    }

    return respondJsonOK(set);
  } else {
    // always reprime the setlist cache whenever this function is called
    primeSetlistTimer?.cancel();

    // get all the setlists
    if (setsByPath.isEmpty) {
      await primeSetlistCache();
    }
    if (setsByPath.isEmpty) {
      return Response.notFound('SETLISTS NOT FOUND: Could not load setlists');
    }

    primeSetlistTimer = Timer(Duration(seconds: 5), () => primeSetlistCache());
    return respondJsonOK(setsCache.toList());
  }
}

FutureOr<Response> songsHandler(Request req) async {
  String songDir = req.params['dir'] ?? '';
  String songFile = req.params['song'] ?? '';
  String cacheKey = songDir.isEmpty
      ? '/'
      : songFile.isEmpty
          ? '/$songDir'
          : '/$songDir/$songFile';
  if (songsByPath.containsKey(cacheKey)) {
    return respondJsonOK(songsByPath[cacheKey]!);
  }

  // return a single song
  if (songFile.isNotEmpty) {
    var song = await songsSetsClient.getSong('$songDir/$songFile');
    if (song != null) {
      songsByPath[cacheKey] = song;
      return respondJsonOK(song);
    }
  } else {
    var songs = await songsSetsClient.getSongs();
    for (var song in songs.responseData!) {
      var basename = song.path.split('/').last;
      var path = '$songDir/$basename';
      songsByPath[path] = song;
      songsByPath[song.path] = song;
    }
    return respondJsonOK(songs.responseData!);
  }
  return Response.notFound('SONGS NOT FOUND: $cacheKey\n');
}

FutureOr<Response> rootHandler(Request req) {
  return staticHandlerHelper(File('public/index.html'), postProcess: (Uint8List bytes) {
    var s = utf8.decode(bytes);
    s = s.replaceAll('[serverEndpoint]', config.serverDirectory);
    return Uint8List.fromList(utf8.encode(s));
  });
}

// cache functions
Future<void> primeSetlistCache() async {
  songsSetsClient.useCache = false;
  var res = await songsSetsClient.getSetlists();
  if (!res.isError) {
    setsByPath.clear();
    setsCache.clear();
    for (var sl in res.responseData!) {
      var path = Uri.decodeComponent(sl.path);

      // we don't want to send the webdav information over the line
      if (config.usedav) sl.path = path.replaceAll('${config.davDir}Sets/', '');

      if (sl.songs.isEmpty) continue;
      setsByPath[path] = sl;
      setsByPath[sl.name] = sl;
      setsCache.add(sl);
    }
    wsManager.broadcast(WebSocketMessage('setlists', {'sets': setsCache}));
  }
}

Future primeSongCache() async {}

// setup functions
void setupClient() {
  if (config.usedav) {
    songsSetsClient = OpenSongDavClient(config.davUrl, config.davDir, config.davUsername, config.davPassword);
  } else {
    songsSetsClient = PCOClient(config.pcoServiceTypeId, config.pcoAppId, config.pcoSecret);
  }
  songsSetsClient.useCache = false;
  wsManager = WebSocketManager(songsSetsClient);
}

void setupCache() async {
  await primeSetlistCache();
  await primeSongCache();
  Timer.periodic(Duration(hours: 6), (timer) async {
    await primeSetlistCache();
    primeSongCache();
  });
}

void startServer() {
  // Configure a pipeline that logs requests.
  // final staticHandler = createStaticHandler('static', defaultDocument: 'index.html', listDirectories: false);
  // final pipeline = Pipeline().addMiddleware(logRequests()).addHandler(_router);

  final router = setupRoutes(config.serverDirectory.isEmpty ? '' : '/${config.serverDirectory}');
  final cascade = Cascade().add(webSocketHandler(wsManager.onConnect)).add(router);

  // TODO: Add middleware to handle blacklist
  final pipeline = Pipeline().addMiddleware(logRequests()).addHandler(cascade.handler);

  // For running in containers, we respect the PORT environment variable.
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? config.serverPort;
  final ip = InternetAddress.anyIPv4;
  io.serve(pipeline, ip, port).then((server) {
    print('Serving at http://${server.address.host}:${server.port}/${config.serverDirectory}');
  });
}

void main(List<String> args) async {
  setupClient();
  setupCache();
  startServer();
}
