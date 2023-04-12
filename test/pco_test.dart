import 'dart:io';

import 'package:planningcenter_api/planningcenter_api.dart';
import 'package:tablet_chords_dart/clients/pco_client.dart';

import '../conf/conf.dart' as config;

void main() async {
  PlanningCenter.init(config.pcoAppId, config.pcoSecret);
  var client = PCOClient(config.pcoServiceTypeId);

  // get recent setlists
  // var sets = await client.getSetlists(perPage: 10);
  // for (var set in sets.responseData!) {
  //   print('${set.name} ${set.description} ${set.date}');
  //   for (var song in set.songs) {
  //     print(' - ${song.title} (${song.key})');
  //   }
  // }

  // get setlists for a plan
  var planId = '64375930';
  var plan = await client.getSetlist('64375930');
  print(plan!.songs.first.toJson());

  exit(0);
}
