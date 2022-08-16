import 'dart:convert';
import 'dart:io';

import 'package:tablet_chords_dart/clients/opensong_dav_client.dart';

import '../conf/conf.dart' as config;

void debug(Object o) {
  print(JsonEncoder.withIndent('  ').convert(o));
}

void main() async {
  var client = OpenSongDavClient(config.davUrl, config.opensongdir, config.davUsername, config.davPassword);
  var sets = await client.getSetlists();
  print(sets);
  for (var set in sets.responseData!) {
    print('Found Set: ${set.name} (${set.songs.length} songs)');
  }

  var set = await client.getSetlist('2022-08-14');
  debug(set!);

  set = await client.getSetlist('2022-08-14', withSongs: true);
  debug(set!);

  // try {
  //   var songs = await client.getSongs();
  //   for (var song in songs.responseData!) {
  //     print('Found Song: ${song.title}');
  //   }
  // } on WebDavException catch (e) {
  //   print(e.cause);
  // }
  // var songs = await client.getSongs();
  // var res = await client.client.ls(path: 'Songs');
  // for (var r in res) print(r);
  // var song = await client.getSong('Archive/All Creatures Of Our God and King');
  // print(song);
  exit(0);
}
