import 'package:planningcenter_api/planningcenter_api.dart';

import '../clients/client.dart';
import '../classes/models.dart';
export 'client.dart';

const credentialsFile = 'pco_credentials.json';

class PCOClient extends SongsSetsClient {
  String serviceTypeId;

  /// The PlanningCenter instance must be initialized first, or an `appId` and `appSecret`
  /// may be supplied to the client for initialization.
  PCOClient(this.serviceTypeId, [String? appId, String? appSecret]) {
    if (appId != null && appSecret != null) {
      PlanningCenter.init(appId, appSecret);
    }
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

  // Future<T?> _load<T>(String fullPath) async {
  //   try {
  //     print('Loading: $fullPath');
  //     var xmlString = await client.downloadToBinaryString(fullPath);
  //     switch (T) {
  //       case Setlist:
  //         return Setlist.fromOpenSongXML(xmlString) as T;
  //       case Song:
  //         return Song.fromOpenSongXML(fullPath, xmlString) as T;
  //       default:
  //         return null;
  //     }
  //   } catch (e) {
  //     print(e);
  //     print('Failed to get data for $fullPath');
  //     return null;
  //   }
  // }

  /// returns setlists paginated
  @override
  Future<ClientResponse<List<Setlist>>> getSetlists({
    int perPage = 25,
    int pageOffset = 0,
    bool withSongs = false,
  }) async {
    List<Setlist> sets = [];
    var plans = await PcoServicesPlan.getFromServiceType(
      serviceTypeId,
      query: PcoServicesPlanQuery(
        orderBy: PcoServicesPlanOrder.sortDate,
        reverse: true,
        perPage: perPage,
        pageOffset: pageOffset,
      ),
    );
    for (var plan in plans.items) {
      var set = Setlist(plan.title, plan.apiPath, plan.lastTimeAt, description: plan.dates);
      var songs = await plan.getItems(
        query: PcoServicesItemQuery(
          includeSong: true,
          includeArrangement: true,
        ),
      );
      for (var item in songs.items) {
        if (item.includedSong == null) continue;
        if (item.includedArrangement == null) continue;
        // we have a song... let's make a local song
        var song = Song.fromPlanningCenterSong(
          item.includedSong!.apiPath,
          plan.lastTimeAt,
          item.includedSong!,
          item.includedArrangement!,
        );
        set.songs.add(song);
      }
      sets.add(set);
    }

    // await _batch(futures);
    return ClientResponse(sets, responseText: '');
  }

  /// `path` should NOT include 'Sets'
  @override
  Future<Setlist?> getSetlist(String path, {bool withSongs = false}) async {
    var realPath = 'Sets/$path';
    // return await _load<Setlist>(realPath);
  }

  /// returns songs paginated
  @override
  Future<ClientResponse<List<Song>>> getSongs({
    int perPage = 25,
    int pageOffset = 0,
  }) async {
    List<Song> songs = [];
    return ClientResponse(songs, responseText: '');
  }

  /// `path` should NOT include 'Songs'
  @override
  Future<Song?> getSong(String path) async {
    var realPath = 'Songs/$path';
  }
}
