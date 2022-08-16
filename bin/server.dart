import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'package:tablet_chords_dart/classes/models.dart';
import 'package:tablet_chords_dart/clients/opensong_dav_client.dart';
import 'package:tablet_chords_dart/clients/pco_client.dart';
import 'package:tablet_chords_dart/handlers/routes.dart';
import 'package:tablet_chords_dart/ws/wsmanager.dart';

import '../conf/conf.dart' as config;

Response respondJsonOK(Object obj) {
  return Response.ok(json.encode(obj), headers: {'Content-Type': 'application/json'});
}

// in-memory caches
final songCache = <String, Song>{};
final setCache = <String, Setlist>{};

// blacklist
const blacklist = {};

// clients for remote data
late SongsSetsClient songsSetsClient;

// the manager for websocket connections
late WebSocketManager wsManager;

// Configure documentation.
const help = '''
API DOCUMENTATION

/ or /index.html  => serve index.html
/static          => serves static files from the static subdirectory
/Sets            => serves list of Setlists
/Sets/NAME       => serves data for Setlist identified by NAME
/Sets/--today--  => will replace --today-- with today's date YYYY-MM-DD before making request
/Sets/--latest-- => will serve the most recent setlist (see implementation below for notes on caching)
/Songs           => serves list of Songs [ BROKEN ]

QUERY VARIABLES
?usecache=1      => will use the most recently cached data for a request
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

WEBSOCKET COMMANDS:
{type: 'alert', data: {text: 'ALERT_TEXT'}}  => will display an alert on every connected tablet
{type: 'control', data: {set: 'SETNAME'}}  => will request control of a setlist
{type: 'key', data: {set: 'SETNAME', songnum: SONGNUM, key: 'KEY'}}  => will send a key update notification
''';

List<DescribedRoute> jsonRoutes = [
  DescribedRoute('/Sets/', 'serves a list of recent Setlists', setsHandler),
  DescribedRoute(
    '/Sets/<path>',
    'serves data for Setlist identified by path. Note, there are two special names available, --today-- and --latest--.',
    setsHandler,
  ),
  DescribedRoute('/Songs/', 'serves a list of all available songs', songsHandler),
  DescribedRoute('/Songs/<dir>/<song>', 'serves an individual song', songsHandler),
];
List<DescribedRoute> staticRoutes = [
  DescribedRoute('/', 'Root route. Serves index.html', rootHandler),
  DescribedRoute(
    '/help',
    'Help route. Serves the contents of the `help` String variable',
    (req) => Response.ok(help, headers: {'content-type': 'text/plain'}),
  ),
  DescribedRoute('/static/<filename>', 'serves hosted js, css, and image files', staticHandler),
];
List<DescribedRoute> webSocketActions = [];

// by setting up the routes this way, we can document our endpoints
// final _router = Router()
//   ..get('$prefix/', _rootHandler)
//   ..get('$prefix/Sets', _setsHandler)
//   ..get('$prefix/Sets/<name>', _setsHandler)
//   ..get('$prefix/Songs', _songsHandler)
//   ..get('$prefix/Songs/<dir>/<name>', _songsHandler)
//   ..get('$prefix/static/<filename>', _myStaticHandler);

final _router = Router();

// FUNCTIONS
void setupRoutes(String prefix) {
  for (var routelist in [staticRoutes, jsonRoutes]) {
    for (var r in routelist) {
      var path = '$prefix${r.path}';
      print('setting up route for $path');
      _router.get(path, r.handler);
    }
  }
}

// static handler
FutureOr<Response> staticHandlerHelper(File f) async {
  final mimeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'js': 'text/javascript',
    'json': 'application/json',
    'html': 'text/html',
  };
  if (await f.exists()) {
    var bytes = await f.readAsBytes();
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
  var f = File('static/$localPath');
  return staticHandlerHelper(f);
}

FutureOr<Response> setsHandler(Request req) async {
  var setPath = req.params['path'];
  var withSongs = false;
  // get a single setlist
  if (setPath != null) {
    withSongs = true;
    Setlist? set;

    if (setCache.containsKey(setPath)) {
      set = setCache[setPath];
    } else {
      set = await songsSetsClient.getSetlist(setPath, withSongs: withSongs);
      if (set != null) {
        setCache[set.path] = set;
        for (var song in set.songs) {
          songCache[song.path] = song;
        }
      }
    }
    if (set == null) {
      return Response.notFound('SETLIST NOT FOUND: ${setPath} could not be found');
    }
    return respondJsonOK(set);
  } else {
    if (setCache.isEmpty) {
      await primeSetlistCache();
    }
    if (setCache.isEmpty) {
      return Response.notFound('SETLISTS NOT FOUND: Could not load setlists');
    }
    return respondJsonOK(setCache.values.toList());
  }
}

FutureOr<Response> songsHandler(Request req) async {
  String? songDir = req.params['dir'];
  String? songFile = req.params['song'];
  return Response.ok('Songs: ${songDir}/${songFile}\n');
}

FutureOr<Response> rootHandler(Request req) {
  return staticHandlerHelper(File('ui/index.html'));
}

// cache functions
Future primeSetlistCache() async {
  songsSetsClient.cache.clear();
  var res = await songsSetsClient.getSetlists();
  if (!res.isError) {
    setCache.clear();
    for (var sl in res.responseData!) {
      setCache[sl.path] = sl;
    }
  }
}

Future primeSongCache() async {}

// setup functions
void setupClient() {
  if (config.usedav) {
    songsSetsClient = OpenSongDavClient(config.davUrl, config.opensongdir, config.davUsername, config.davPassword);
  } else {
    songsSetsClient = PCOClient(config.pcoServiceTypeId);
  }
  songsSetsClient.useCache = false;
  wsManager = WebSocketManager(songsSetsClient);
}

void setupCache() async {
  await primeSetlistCache();
  await primeSongCache();
  setupTimers();
}

void setupTimers() {
  Timer.periodic(Duration(hours: 6), (timer) async {
    await primeSetlistCache();
    primeSongCache();
  });
}

void startServer() {
  // Configure a pipeline that logs requests.
  // final staticHandler = createStaticHandler('static', defaultDocument: 'index.html', listDirectories: false);
  // final pipeline = Pipeline().addMiddleware(logRequests()).addHandler(_router);

  // var handler = Cascade().add(webSocketHandler(_wsConnectHandler)).add(_myStaticHandler).add(_application).add(_router).handler;
  var handler = Cascade().add(webSocketHandler(wsManager.onConnect)).add(_router).handler;

  // For running in containers, we respect the PORT environment variable.
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? config.serverPort;
  final ip = InternetAddress.anyIPv4;
  io.serve(handler, ip, port).then((server) {
    print('Serving at http://${server.address.host}:${server.port}/${config.serverDirectory}');
  });
}

void main(List<String> args) async {
  setupClient();
  setupCache();
  setupRoutes(config.serverDirectory.isEmpty ? '' : '/${config.serverDirectory}');
  startServer();
}
