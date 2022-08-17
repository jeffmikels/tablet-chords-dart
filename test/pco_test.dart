import 'dart:io';

import 'package:planningcenter_api/planningcenter_api.dart';
import 'package:tablet_chords_dart/clients/pco_client.dart';

import '../conf/conf.dart' as config;

void main() async {
  PlanningCenter.init(config.pcoAppId, config.pcoSecret);
  var sundayWorship = '1169425';
  var planId = '59506404';

  var client = PCOClient(config.pcoServiceTypeId);
  var sets = await client.getSetlists(perPage: 10);
  for (var set in sets.responseData!) {
    print('${set.name} ${set.description} ${set.date}');
    for (var song in set.songs) {
      print(' - ${song.title}');
    }
  }
  exit(0);
}
