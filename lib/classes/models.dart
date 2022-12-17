import 'package:planningcenter_api/planningcenter_api.dart';
import 'package:xml/xml.dart';

import 'opensong.dart';
import 'dart:convert' as cv;

class Setlist {
  String path = '';
  String name = '';
  DateTime date;
  String description = '';
  List<Song> songs = [];

  /// OpenSong Sets look like this
  // <?xml version="1.0" encoding="UTF-8"?>
  // <set name="2022-01-02">
  //   <slide_groups>
  //   <slide_group name="So Will I (100 Billion X)" type="song" presentation="" path="Archive/"/>
  //   <slide_group name="The Love Of Jesus" type="song" presentation="" path="2022/"/>
  //   <slide_group name="Jesus We Love You" type="song" presentation="" path="2021/"/>
  //   <slide_group name="==== SERMON ==============" type="song" presentation="" path="- ADMIN/"/>
  //   <slide_group name="Famous For (I Believe)" type="song" presentation="" path="2021/"/>
  //   <slide_group name="==== ALTERNATES ===========" type="song" presentation="" path="- ADMIN/"/>
  //   <slide_group name="Abide With Me" type="song" presentation="" path="Archive/"/>
  //   <slide_group name="I Am Loved" type="song" presentation="" path="2021/"/>
  //   <slide_group name="Touch of Heaven" type="song" presentation="" path="2021/"/>
  //   <slide_group name="Yours (Acoustic)" type="song" presentation="" path="2021/"/>
  //   <slide_group name="Tremble" type="song" presentation="" path="2021/"/>
  // </slide_groups></set>
  Setlist.fromOpenSongXML(this.path, this.date, String xmlString, {this.description = ''}) {
    var doc = XmlDocument.parse(xmlString);
    var elSet = doc.findElements('set');
    if (elSet.isNotEmpty) {
      name = elSet.first.getAttribute('name')!;
    } else {
      name = 'invalid set data';
      return;
    }
    var groups = elSet.first.findAllElements('slide_group');
    for (var group in groups) {
      var type = group.getAttribute('type')!;
      if (type == 'song') {
        var title = group.getAttribute('name') ?? '';
        var folder = group.getAttribute('path') ?? '';
        var s = Song()
          ..title = title
          ..path = '$folder$title';
        songs.add(s);
      }
    }
  }

  factory Setlist.fromPlanningCenterPlan(PcoServicesPlan plan) {
    if (plan.title.isEmpty) plan.title = plan.dates;
    return Setlist(plan.title, plan.id!, plan.lastTimeAt, description: plan.dates);
  }

  Setlist(this.name, this.path, this.date, {this.description = ''});

  toJson() => {
        'path': path,
        'name': name,
        'date': date.toIso8601String(),
        'description': description,
        'songs': songs,
      };

  String get json => cv.json.encode(toJson());
}

enum SongLineType { comment, heading, chords, lyric }

class SongLine {
  SongLineType type = SongLineType.lyric;
  String content = '';

  bool get monospace => type == SongLineType.chords || type == SongLineType.lyric;
}

class Song {
  bool loaded = false;
  String path = '';
  DateTime date = DateTime.now();

  String title = '';
  String lyrics = '';
  String openSongLyrics = '';
  String chordProLyrics = '';
  double bpm = 0;
  String key = 'A';
  String meter = '4/4';
  String writer = '';
  String copyright = '';
  String ccli = '';

  bool isOpenSongFormat = false;
  bool get isChordProFormat => !isOpenSongFormat;

  String get formattedCcli => ccli == '' ? '' : 'CCLI #$ccli';
  String get formattedCopyright => copyright == '' ? '' : 'Copyright $copyright';

  Song();

  Song.fromOpenSongXML(this.path, this.date, String xmlString) {
    fromOpenSongXML(xmlString);
  }

  Song.fromPlanningCenterSong(
    this.path,
    this.date,
    PcoServicesSong song,
    PcoServicesArrangement arrangement,
  ) {
    fromPlanningCenterSong(song, arrangement);
  }

  void copyFrom(Song other) {
    path = other.path;
    title = other.title;
    lyrics = other.lyrics;
    bpm = other.bpm;
    key = other.key;
    ccli = other.ccli;
    writer = other.writer;
    copyright = other.copyright;
    isOpenSongFormat = other.isOpenSongFormat;
  }

  void fromOpenSongXML(String xmlString) {
    var s = OpenSongSong.fromXML(path, xmlString);
    loaded = true;
    title = s.title;
    lyrics = s.lyrics;
    bpm = s.bpm;
    key = s.key;
    ccli = s.ccli;
    writer = s.author;
    copyright = s.copyright;

    isOpenSongFormat = true;
  }

  void fromPlanningCenterSong(PcoServicesSong song, PcoServicesArrangement arrangement) {
    loaded = true;
    title = song.title;
    ccli = song.ccliNumber.toString();
    writer = song.author;
    copyright = song.copyright;

    // all arrangements have these items at least
    key = arrangement.chordChartKey;
    bpm = arrangement.bpm.toDouble();
    lyrics = arrangement.chordChart;

    // determine if the lyrics are chordpro or opensong
    // if any line begins with a `.` or a `;`, then treat it as opensong format
    for (var line in lyrics.split('\n')) {
      if (line.startsWith(RegExp(r'[\.;]'))) {
        isOpenSongFormat = true;
        break;
      }
    }

    if (!isOpenSongFormat) {
      lyrics = convertChordProToOpensong(lyrics);
    }
  }

  /// the tablet interface does a better job with OpenSong style lyrics
  /// because they can be displayed with a monospace font.
  ///
  /// Here is an example chordpro item
  /// {<i>BPM 68</i>}
  ///
  /// {<i>THE QUARANTINE EDITION has female lead, and changes the melody some</i>}
  /// {<i>MALE KEY C</i>}
  /// {<i>FEMALE KEY G</i>}
  /// {<i>starts on the 6</i>}
  ///
  /// KEY
  /// [G]
  ///
  /// INTRO
  /// [| Em \ C6 \ || G \ \ \ || Em \ C6 \ || G \ \ \ |]
  ///
  /// VERSE 1
  /// [Em]   There's a grace when the [C6]heart is under [G]fire
  /// [Em]   Another way when the [C6]walls are closing in[G]
  /// [Em]   And when I look at the [C6]space between
  /// Where I [G]used to be and this [D/G]reckoning
  /// [Em]   I know I will [C6]never be alone[G]
  ///
  /// CHORUS 1
  /// There was another in the [Em]fire s[C6]tanding next to m[G]e
  /// ...
  static String convertChordProToOpensong(String lyrics) {
    /// https://pcoservices.zendesk.com/hc/en-us/articles/204262464#UUID-6da2e7d8-e30c-6831-96a0-d934f4dfabdb

    var ignoreLines = <String>['TRANSPOSE', 'REDEFINE', 'COLUMN_BREAK', 'PAGE_BREAK'];
    var commentRegex = RegExp('{+(.*)}+');
    var htmlTagRegex = RegExp('<.*?>');
    var sectionRegex = RegExp(r'^[A-Z 0-9]+$'); // headings are in all caps
    var chordLineRegex = RegExp(r'^\[([^[]+?)\]$');
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
      }
      res.add(chordline.join());
      res.add(lyricline.join());
    }
    return res.join('\n');
  }

  toJson() => {
        'path': path,
        'date': date.toIso8601String(),
        'title': title,
        'lyrics': lyrics,
        'bpm': bpm,
        'key': key,
        'meter': meter,
        'author': writer,
        'copyright': copyright,
        'ccli': ccli,
        'formatted-ccli': formattedCcli,
        'formatted-copyright': formattedCopyright,
        'format': isOpenSongFormat ? 'opensong' : 'chordpro',
        'abc': '', // TODO: add 'abc' field
      };

  String get json => cv.json.encode(toJson());
}
