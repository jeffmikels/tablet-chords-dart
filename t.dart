String convertChordProToOpensong(String lyrics) {
  /// https://pcoservices.zendesk.com/hc/en-us/articles/204262464#UUID-6da2e7d8-e30c-6831-96a0-d934f4dfabdb

  var ignoreLines = <String>['TRANSPOSE', 'REDEFINE', 'COLUMN_BREAK', 'PAGE_BREAK'];
  var commentRegex = RegExp('{+(.*)}+');
  var htmlTagRegex = RegExp('<.*?>');
  var sectionRegex = RegExp(r'^[A-Z 0-9]+$'); // headings are in all caps
  var chordLineRegex = RegExp(r'^\[([^[]+?)\]$');
  var chordRegex = RegExp(r'\[(.*?)\]');
  var res = <String>[];
  for (var l in lyrics.split('\n')) {
    l = l.trim(); // remove trailing whitespace like \r

    // ignore certain lines
    for (var il in ignoreLines) {
      if (l.startsWith(il)) continue;
    }

    // handle comments and abort further processing
    if (l.startsWith(commentRegex)) {
      l = l.replaceAllMapped(commentRegex, (m) => m.group(1)!).replaceAll(htmlTagRegex, '');
      res.add('; $l');
      continue;
    }

    if (l.startsWith(sectionRegex)) {
      res.add('[$l]');
      continue;
    }

    // if there are no square brackets, add it as is
    if (!l.contains('[')) {
      res.add(' $l');
      continue;
    }

    // if the line has brackets around the whole thing, it is a "chord line"
    if (l.startsWith(chordLineRegex)) {
      if (!l.contains(' ')) {
        l = l.substring(1, l.length - 1);
      }
      res.add('.$l');
      continue;
    }

    // if we have made it this far, we have a line with chords in it
    var chordline = <String>['.'];
    var lyricline = <String>[' '];
    int chordLenCompensation = 0;
    bool inChord = false;
    for (var char in l.split('')) {
      switch (char) {
        case '[':
          inChord = true;
          chordLenCompensation = 0;
          continue;
        case ']':
          inChord = false;
          continue;
      }
      if (inChord) {
        chordLenCompensation++;
        chordline.add(char);
      } else {
        lyricline.add(char);
        if (chordLenCompensation-- < 1) chordline.add(' ');
      }
      print("$chordLenCompensation");
      print(chordline.join(''));
      print(lyricline.join(''));
      print(l);
    }
    res.add(chordline.join());
    res.add(lyricline.join());
  }
  return res.join('\n');
}

void main() {
  print(convertChordProToOpensong(r'''
{<i>BPM 68</i>}
{<i>THE QUARANTINE EDITION has female lead, and changes the melody some</i>}
{<i>MALE KEY C</i>}
{<i>FEMALE KEY G</i>}
{<i>starts on the 6</i>}

KEY
[G]

INTRO
[| Em \ C6 \ || G \ \ \ || Em \ C6 \ || G \ \ \ |]

VERSE 1
[Em]   There's a grace when the [C6]heart is under [G]fire
[Em]   Another way when the [C6]walls are closing in[G]
[Em]   And when I look at the [C6]space between
Where I [G]used to be and this [D/G]reckoning
[Em]   I know I will [C6]never be alone[G]
'''));
}


// void main() {
//   var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
//   var source = 'Wed, 10 Aug 2022 17:21:38 GMT';
//   var match = RegExp(r'.*?, (\d+) (.*?) (\d+) (\d+):(\d+):(\d+)').firstMatch(source);
//   if (match == null) print('none');
//   var day = int.parse(match!.group(1)!);
//   var mon = months.indexOf(match.group(2)!) + 1;
//   var year = int.parse(match.group(3)!);
//   var h = int.parse(match.group(4)!);
//   var m = int.parse(match.group(5)!);
//   var s = int.parse(match.group(6)!);
//   print(DateTime(year, mon, day, h, m, s));
// }
