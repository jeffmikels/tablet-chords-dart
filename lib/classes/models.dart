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
  double bpm = 0;
  String key = 'A';
  String meter = '4/4';
  String writer = '';
  String copyright = '';
  String ccli = '';

  bool isOpenSongFormat = false;
  bool get isChordProFormat => !isOpenSongFormat;

  String get formattedCcli => ccli == '' ? '' : 'CCLI #${ccli}';
  String get formattedCopyright => copyright == '' ? '' : 'Copyright ${copyright}';

  Song();

  Song.fromOpenSongXML(this.path, this.date, String xmlString) {
    fromOpenSongXML(xmlString);
  }
  Song.fromPlanningCenterSong(this.path, this.date, PcoServicesSong song, PcoServicesArrangement arrangement) {
    fromPlanningCenterSong(song, arrangement);
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

    key = arrangement.chordChartKey;
    bpm = arrangement.bpm;
    lyrics = arrangement.chordChart;

    // determine if the lyrics are chordpro or opensong
    // if any line begins with a `.` or a `;`, then treat it as opensong format
    for (var line in lyrics.split('\n')) {
      if (line.startsWith(RegExp(r'[\.;]'))) {
        isOpenSongFormat = true;
        break;
      }
    }
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
        'abc': '', // TODO: add 'abc' field
      };

  String get json => cv.json.encode(toJson());
}
