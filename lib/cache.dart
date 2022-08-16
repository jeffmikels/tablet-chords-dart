// implements a map, but wraps it with a `primer` function
// so the class remembers how to populate itself
class Cache<T> {
  final Map<String, T> _data = {};
  Future<Map<String, T>> Function()? primer;

  operator [](String key) => _data[key];
  operator []=(String key, T t) => _data[key] = t;

  Cache({this.primer}) {
    prime();
  }

  void clear() => _data.clear();
  void addAll(Map<String, T> other) => _data.addAll(other);

  void prime() async {
    if (primer == null) return;
    var res = await primer!();
    _data.clear();
    _data.addAll(res);
  }
}
