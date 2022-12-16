import '../clients/client.dart';
import '../classes/models.dart';

import 'dav.dart';
export 'client.dart';

// import 'package:webdav_client/webdav_client.dart' as webdav;

// extension ClientReadString on webdav.Client {
//   Future<String> readString(String path) async {
//     var bytes = await read(path);
//     return utf8.decode(bytes);
//   }
// }

class OpenSongDavClient extends SongsSetsClient {
  late WebDavClient client;
  String baseUrl;
  String openSongDir = '';

  OpenSongDavClient(this.baseUrl, this.openSongDir, String username, String password) {
    var uri = Uri.parse(baseUrl);
    client = WebDavClient(uri, username, password, basePath: openSongDir);
  }

  Future<void> _batch(List<Future> futures, [int concurrent = 10]) async {
    if (futures.length < concurrent) {
      await Future.wait(futures);
      return;
    } else {
      var tmp = futures.sublist(0, concurrent);
      await Future.wait(tmp);
      futures.removeRange(0, concurrent);
      await _batch(futures);
    }
  }

  Future<T?> _loadPath<T>(String fullPath) async {
    try {
      print('Loading: $fullPath');
      var file = await client.stat(fullPath);
      return _loadFile(file);
    } catch (e) {
      print(e);
      print('Failed to find on server: $fullPath');
      return null;
    }
  }

  Future<T?> _loadFile<T>(FileInfo file) async {
    var cleanPath = Uri.decodeComponent(file.path);
    try {
      print('Loading: $cleanPath');
      late String xmlString;
      if (useCache && cache.containsKey(cleanPath)) {
        xmlString = cache[cleanPath]!;
      } else {
        xmlString = await client.downloadToBinaryString(file.path);
        cache[cleanPath] = xmlString;
      }
      switch (T) {
        case Setlist:
          return Setlist.fromOpenSongXML(cleanPath, file.modified, xmlString) as T;
        case Song:
          return Song.fromOpenSongXML(cleanPath, file.modified, xmlString) as T;
        default:
          return null;
      }
    } catch (e) {
      print(e);
      print('Failed to get data for "$cleanPath"');
      return null;
    }
  }

  /// returns setlists paginated
  @override
  Future<ClientResponse<List<Setlist>>> getSetlists({
    int perPage = 25,
    int pageOffset = 0,
  }) async {
    List<Setlist> sets = [];
    List<FileInfo> files = await client.ls(path: 'Sets');
    List<Future> futures = [];
    for (var f in files) {
      if (f.basename.startsWith('.')) continue;
      futures.add(_loadFile<Setlist>(f).then((e) {
        if (e != null) sets.add(e);
      }));
    }
    await _batch(futures);
    return ClientResponse(sets, responseText: '');
  }

  /// `path` should NOT include 'Sets'
  @override
  Future<Setlist?> getSetlist(String path, {bool withSongs = false}) async {
    if (!path.startsWith('Sets')) path = 'Sets/$path';
    var setlist = await _loadPath<Setlist>(path);
    if (setlist != null && withSongs) {
      var futures = <Future>[];
      var songs = <Song>[];
      for (var s in setlist.songs) {
        futures.add(getSong(s.path).then((e) {
          if (e != null) songs.add(e);
        }));
      }
      await _batch(futures);
      // match setlist songs to new songs
      for (var song in setlist.songs) {
        try {
          var other = songs.firstWhere((s) => s.path.endsWith(song.path));
          song.copyFrom(other);
        } catch (e) {
          print(e);
        }
      }
    }
    return setlist;
  }

  /// returns songs paginated
  @override
  Future<ClientResponse<List<Song>>> getSongs({
    int perPage = 25,
    int pageOffset = 0,
  }) async {
    List<Song> songs = [];
    // List<Future<List<FileInfo>>> futures = [];
    List<Future> futures = [];
    List<FileInfo> dirs = await client.ls(path: 'Songs');
    for (var d in dirs) {
      print('Found Dir: ${d.path}');
      // futures.add(getSongFolder(d.path).then((items) => songs.addAll(items)));
      await getSongFolder(d.path).then((items) => songs.addAll(items));
    }
    await _batch(futures);
    return ClientResponse(songs, responseText: '');
  }

  Future<List<Song>> getSongFolder(String fullPath) async {
    print('Loading Song Folder: $fullPath');
    List<Song> songs = [];
    List<Future> futures = [];
    List<FileInfo> files = await client.ls(path: fullPath);
    for (var f in files) {
      if (f.basename.startsWith('.')) continue;
      futures.add(_loadFile<Song>(f).then((e) {
        if (e != null) songs.add(e);
      }));
    }
    await _batch(futures);
    return songs;
  }

  /// `path` should NOT include 'Songs'
  @override
  Future<Song?> getSong(String path) async {
    var realPath = 'Songs/$path';
    return await _loadPath<Song>(realPath);
  }
}
