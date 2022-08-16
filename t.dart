void main() {
  var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var source = 'Wed, 10 Aug 2022 17:21:38 GMT';
  var match = RegExp(r'.*?, (\d+) (.*?) (\d+) (\d+):(\d+):(\d+)').firstMatch(source);
  if (match == null) print('none');
  var day = int.parse(match!.group(1)!);
  var mon = months.indexOf(match.group(2)!) + 1;
  var year = int.parse(match.group(3)!);
  var h = int.parse(match.group(4)!);
  var m = int.parse(match.group(5)!);
  var s = int.parse(match.group(6)!);
  print(DateTime(year, mon, day, h, m, s));
}
