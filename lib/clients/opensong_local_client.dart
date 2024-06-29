import 'dart:io';
import '../clients/client.dart';
import '../classes/models.dart';
import '../conf/conf.dart' as config;
export 'client.dart';

// import 'package:webdav_client/webdav_client.dart' as webdav;

// extension ClientReadString on webdav.Client {
//   Future<String> readString(String path) async {
//     var bytes = await read(path);
//     return utf8.decode(bytes);
//   }
// }

class OpenSongLocalClient extends SongsSetsClient {
  String openSongDir = '';

  OpenSongLocalClient(this.openSongDir);

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

  Future<T?> _loadPath<T>(String path) async {
    if (!path.startsWith(openSongDir)) path = '$openSongDir$path';
    var file = File(path);
    if (await file.exists()) {
      return _loadFile(file);
    }
    return null;
  }

  Future<T?> _loadFile<T>(File file) async {
    // also remove the word 'Sets' or 'Songs'
    var relativePath = file.path.replaceFirst(openSongDir, '');
    DateTime lastModified = await file.lastModified();
    try {
      print('Loading: ${file.path}');
      String xmlString = '';
      var cached = cache[file.path];
      if (cached != null && !cached.lastModified.isBefore(lastModified)) {
        xmlString = cached.data;
      } else {
        xmlString = await file.readAsString();
        cache[file.path] = CachedItem(file.path, lastModified, xmlString);
      }
      switch (T) {
        case Setlist:
          return Setlist.fromOpenSongXML(relativePath, lastModified, xmlString) as T;
        case Song:
          return Song.fromOpenSongXML(relativePath, lastModified, xmlString) as T;
        default:
          return null;
      }
    } catch (e) {
      print(e);
      print('Failed to get data for "$relativePath"');
      return null;
    }
  }

  @override
  Future<void> updateCache() async {
    List<Future> promises = [];
    for (var fullPath in cache.keys) {
      var file = File(fullPath);
      promises.add(_loadFile(file));
    }
    await Future.wait(promises);
    return;
  }

  /// returns setlists paginated
  @override
  Future<ClientResponse<List<Setlist>>> getSetlists({
    int perPage = 25,
    int pageOffset = 0,
  }) async {
    List<Setlist> sets = [];
    List<FileSystemEntity> files = await Directory('${openSongDir}Sets').list().toList();
    List<Future> futures = [];
    for (var f in files) {
      var basename = f.path.split('/').last;
      if (basename.startsWith('.')) continue;
      futures.add(_loadPath<Setlist>(f.path).then((e) {
        if (e != null) sets.add(e);
      }));
    }
    await _batch(futures);
    return ClientResponse(sets, responseText: '');
  }

  /// `path` should NOT include 'Sets'
  @override
  Future<Setlist?> getSetlist(String path, {bool withSongs = false}) async {
    print('GET SETLIST: ${path}');
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
    List<FileSystemEntity> dirs = await Directory('${openSongDir}Songs').list().toList();
    for (var d in dirs) {
      if (d is! Directory) continue;
      if (config.folderIgnoreMatch != null && d.path.contains(config.folderIgnoreMatch!)) continue;

      print('Found Dir: ${d.path}');

      futures.add(getSongFolder(d.path).then((items) => songs.addAll(items)));
      // await getSongFolder(d.path).then((items) => songs.addAll(items));
    }
    await _batch(futures);
    return ClientResponse(songs, responseText: '');
  }

  /// this should be a specific song folder... not "Songs"
  Future<List<Song>> getSongFolder(String fullPath) async {
    print('Loading Song Folder: $fullPath');
    List<Song> songs = [];
    List<Future> futures = [];
    List<FileSystemEntity> items = await Directory(fullPath).list().toList();
    for (var f in items) {
      if (f is Directory) continue;
      if (config.songIgnoreMatch != null && f.path.contains(config.songIgnoreMatch!)) continue;

      var basename = f.path.split('/').last;
      if (basename.startsWith('.')) continue;
      futures.add(_loadPath<Song>(f.path).then((e) {
        if (e != null) songs.add(e);
      }));
    }
    await _batch(futures);
    songs.sort(
      (a, b) => a.title.compareTo(b.title),
    );
    return songs;
  }

  /// `path` should NOT include 'Songs'
  @override
  Future<Song?> getSong(String path) async {
    var realPath = 'Songs/$path';
    return await _loadPath<Song>(realPath);
  }
}
