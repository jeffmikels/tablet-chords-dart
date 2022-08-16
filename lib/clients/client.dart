import '../classes/models.dart';

abstract class SongsSetsClient {
  bool lastRequestHasMore = false;
  int nextOffset = 0;

  final Map<String, String> cache = {};
  bool useCache = true;

  /// returns setlists paginated
  Future<ClientResponse<List<Setlist>>> getSetlists({
    int perPage = 25,
    int pageOffset = 0,
  });
  Future<Setlist?> getSetlist(String path, {bool withSongs = false});

  /// returns songs paginated
  Future<ClientResponse<List<Song>>> getSongs({
    int perPage = 25,
    int pageOffset = 0,
  });
  Future<Song?> getSong(String path);

  /// TODO: should we allow song and setlist SAVING?
}

class ClientResponse<T> {
  bool isError = false;
  bool hasMore = false;
  int nextOffset = 0;
  int page = 0;

  T? responseData;
  String responseText;

  ClientResponse(
    this.responseData, {
    required this.responseText,
    this.isError = false,
    this.hasMore = false,
    this.nextOffset = 0,
    this.page = 1,
  });
}
