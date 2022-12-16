import 'dart:io';

import 'package:xml/xml.dart';

extension FileBasename on FileSystemEntity {
  String get basename => path.split('/').last;
}

class SongInvalidDataException implements Exception {
  String path = '';
  String errMsg() => 'Song file contained invalid data: $path';
  SongInvalidDataException(this.path) : super();
}

class SetInvalidDataException implements Exception {
  String path = '';
  String errMsg() => 'Set file contained invalid data: $path';
  SetInvalidDataException(this.path) : super();
}

class OpenSongSong {
  late String path;

  // all getters
  String get basename => _file?.basename ?? path;
  DateTime? get mTime => _stat?.changed;

  // items directly from the xml data
  String get title => _songData?.getElement('title')?.text.trim() ?? basename;
  String get author => _songData?.getElement('author')?.text.trim() ?? '';
  String get copyright => _songData?.getElement('copyright')?.text.trim() ?? '';
  String get ccli => _songData?.getElement('ccli')?.text.trim() ?? '';
  String get xmlkey => _songData?.getElement('key')?.text.trim() ?? 'C';
  String get lyrics => _songData?.getElement('lyrics')?.text ?? '';
  int? get ccliNumber => int.tryParse(ccli);

  // allowed setters
  // set lyrics(String s) {
  //   print(lyrics);
  //   if (_songData!.getElement('lyrics')!.firstChild == null) {
  //     _songData!.getElement('lyrics')!.children.add(XmlText(s));
  //   } else {
  //     (_songData!.getElement('lyrics')!.firstChild as XmlText).text = s;
  //   }
  // }

  set title(String s) => setSongTag('title', s);
  set author(String s) => setSongTag('author', s);
  set copyright(String s) => setSongTag('copyright', s);
  set ccli(String s) => setSongTag('ccli', s);
  set xmlkey(String s) => setSongTag('key', s);
  set ccliNumber(int? s) => ccli = s?.toString() ?? '';
  set lyrics(String s) => setSongTag('lyrics', s);

  void setSongTag(String tagname, String value) {
    // ensure _songData
    if (_songData == null) {
      _doc.children.add(XmlElement(XmlName('song')));
    }

    // ensure tag
    var el = _songData!.getElement(tagname);
    if (el == null) {
      el = XmlElement(XmlName(tagname));
      _songData!.children.add(el);
    }

    // ensure text
    var val = XmlText(value);
    if (el.children.isEmpty) {
      el.children.add(val);
    } else {
      el.children[0] = val;
    }
  }

  // items that might be overridden by the lyrics
  String get key => lyricskey ?? xmlkey;
  String? lyricskey;
  double bpm = 0;

  // private data fields
  File? _file;
  FileStat? _stat;

  late String _xml = '';
  late XmlDocument _doc;
  XmlElement? get _songData => _doc.getElement('song');

  String get xml => _doc.toXmlString();

  OpenSongSong(this.path) {
    loadSong();
  }

  OpenSongSong.fromXML(this.path, String xmlString) {
    _xml = xmlString;
    _parseSong();
  }

  void loadSong() {
    _file = File(path);
    if (!_file!.existsSync()) throw FileSystemException('Song File Not Found', path);
    _stat = _file!.statSync();
    _xml = _file!.readAsStringSync();
    _parseSong();
  }

  void _parseSong() {
    print('Parsing song data from $path');
    try {
      _doc = XmlDocument.parse(_xml);
    } on XmlParserException catch (e) {
      print(e.toString());
      throw SongInvalidDataException(path);
    }
    if (_songData == null) {
      // print('Could not find a `song` element in the source XML.');
      throw SongInvalidDataException(path);
    }

    _checkLyricsKeyAndBpm();
  }

  @override
  String toString() => xml;

  /// make the string lowercase, but capitalize references to a key
  String formatComment(String s) {
    return s;
  }

  // return possible keys for each chord
  List<int> keySemitonesFromChord(int chordSemitone, String color) {
    if (color == 'minor') {
      // minor chords might be the third, second, or sixth of the scale
      return [
        (chordSemitone + 3) % 12,
        (chordSemitone + 12 - 2) % 12,
        (chordSemitone + 12 - 4) % 12,
      ];
    } else if (color == 'maj7') {
      // major7 chords are usually the 6m with a 4 added
      // so they usually function as the fourth of the scale
      // but they are also in the scale of the 6m
      // since we don't report minor keys, for now, we just guess the 4
      return [
        (chordSemitone + 12 - 5) % 12,
      ];
    } else {
      // major chords are usually the 1, 4, 5 of the scale
      return [
        chordSemitone % 12,
        (chordSemitone + 12 - 5) % 12,
        (chordSemitone + 12 - 7) % 12,
      ];
    }
  }

  String guessKeyFromLyrics() {
    var cs = RegExp(r'[^\/](([ABCDEFG][b#]?)(maj7|Maj7|M7|m)?[^\s\/]*)');
    var chordletters = 'A A# B C C# D D# E F F# G G# A Bb B C Db D Eb E F Gb G Ab'.split(' ');
    chordletters.addAll(chordletters.toList());
    // var realKeyMap = [12, 13, 14, 15, 16, 17, 18, 19, 20, 9, 22, 23];

    var possible = [];
    var seen = [];
    // to compute the key:
    // for the first chord, compute the possible keys
    // for each subsequent chord, remove impossible keys until one remains
    // once a key is computed... exit the loop

    // label for interior breakpoints
    keySearch:
    for (var line in lyrics.split('\n')) {
      if (line.startsWith('.')) {
        // Log(line);
        // var cs = /[^\/\.](([ABCDEFG][b#]?)(m(?!a))?[^\s\/]*)/g;
        // ignore bass chords (immediately following a slash)
        var matches = cs.allMatches(line);
        for (var m in matches) {
          String cname = m[1]!;
          if (seen.contains(cname)) continue;
          seen.add(cname);
          String cletter = m[2]!;
          String color = m[3] ?? 'major';
          if (color == 'Maj7' || color == 'M7') color = 'maj7';
          if (color == 'm') color = 'minor';

          print('Found Chord: $cname => $cletter ($color)');
          var cindex = chordletters.indexOf(cletter);
          if (cindex >= 0) {
            // is this the first chord we have seen?
            if (possible.isEmpty) {
              possible = keySemitonesFromChord(cindex, color);
            } else {
              var newPossible = keySemitonesFromChord(cindex, color);
              possible = possible.where((e) => newPossible.contains(e)).toList();
            }
            var possibleString = possible.map((e) => chordletters[e]);
            print('$cname => $possibleString');
            if (possible.length == 1) {
              break keySearch;
            }
          }
        }
      }
    }

    var key = 'C';
    if (possible.isNotEmpty) {
      // only use flat key signatures except for F#
      var realKeyIndex = possible[0] + 12;
      if (realKeyIndex == 9 + 12) realKeyIndex = 9; // CHANGE Gb to F#

      key = chordletters[realKeyIndex];
      if (possible.length == 1) {
        print('Determined Key Is: $key');
      } else {
        print('Guessed Key Is: $key');
      }
    } else {
      print('Key could not be determined. Guessing "C" just because.');
    }
    // lyrics = ';SAVED KEY: $key ($verb)\n' + lyrics;
    lyrics = lyrics.replaceFirst(RegExp(r'^\.'), '[key]\n.$key\n\n.');
    // print(_doc.toXmlString());
    return key;
  }

  void _checkLyricsKeyAndBpm() {
    // look for [key] signature
    var keysearch = RegExp(r'\[key\]\s+\.\s*([^\s]+)', caseSensitive: false);
    lyricskey = keysearch.firstMatch(lyrics)?.group(1) ?? guessKeyFromLyrics();

    // look for tempo options
    var bpmsearch = RegExp(r';\s*BPM:?\s*(\d+)|;\s*(\d+)\s*BPM', caseSensitive: false);
    var bpmmatch = bpmsearch.firstMatch(lyrics);
    bpm = double.tryParse(bpmmatch?.group(1) ?? bpmmatch?.group(2) ?? '0') ?? 0;
  }

  // void convertToChordPro() {}

  /// Planning Center uses ChordPro Lyrics
  /// with some additional codes available
  /// https://pcoservices.zendesk.com/hc/en-us/articles/204262464#Lyrics&Chords
  ///
  /// {note}        styled comment for chord chart and lyric PDFs
  /// {{note}}      styled comment for only chord chart PDFs
  /// COLUMN_BREAK  manual column break
  /// PAGE_BREAK    manual page break
  /// ALL CAPS      section heading (chordpro parsing ignored)
  /// TRANSPOSE KEY +n trigger automatic chord transposing
  /// REDEFINE KEY +n  alert system of manual transposition
  /// Styled comments can use <b>, <i>, <strong>, or <em> html tags
  String planningCenterChordPro() {
    /// opensong lyrics have a code at the beginning of each line
    /// " " means lyric line
    /// ";" means comment line
    /// "[" means section identifier
    /// "---" means column break
    /// "." means chord line

    var sectionMap = {
      'I': 'INSTRUMENTAL',
      'C': 'CHORUS',
      'V': 'VERSE',
      'T': 'TAG',
      'B': 'BRIDGE',
      'P': 'PRE-CHORUS',
    };
    List<String> converted = [];
    var lines = lyrics.replaceAll('\r\n', '\n').split('\n'); // in case of Windows line endings
    String lastChordLine = '';
    bool usedChords = false;
    bool ignoreNextLine = false;
    for (var fullLine in lines) {
      if (ignoreNextLine) {
        ignoreNextLine = false;
        continue;
      }

      print('PARSING: $fullLine');
      if (fullLine.length < 2) fullLine += '  ';
      var char = fullLine.substring(0, 1);
      var line = fullLine.substring(1);

      // should we output the previous chord line?
      if (char != ' ' && lastChordLine.isNotEmpty && !usedChords) {
        converted.add('[$lastChordLine]');
        usedChords = true;
      }

      switch (char) {
        // comment line
        case ';':
          // if we don't make the comments bold, Planning Center randomly bolds words in all caps
          // but if we do make them bold, they look the same as the section headings :-(
          // solution is to make comments lowercase or titleCase
          line = formatComment(line.trim());
          converted.add('{<i>$line</i>}');
          break;
        // section line
        case '[':
          line = line.trim();
          var sectionContent = line.replaceAll('[', '').replaceAll(']', '').toUpperCase();
          // if (sectionContent == 'KEY') {
          //   ignoreNextLine = true;
          //   continue;
          // }
          // the extra 'C' is for sections named PC for pre-chorus
          var matches = RegExp(r'^([ICVTBP])C?(\d?)$').firstMatch(sectionContent);
          if (matches != null) {
            var code = matches.group(1);
            var num = matches.group(2);
            sectionContent = sectionMap[code]!;
            if (num != null) sectionContent += ' $num';
          }
          converted.add('\n');
          converted.add(sectionContent);
          break;

        // column breaks
        case '-':
          converted.add('\nCOLUMN_BREAK\n');
          break;

        // chord lines
        case '.':
          // in OpenSong, we sometimes use square brackets in chord lines to indicate
          // measures or optional chords... ChorPro won't like that, so we need to
          // replace square brackets in chord lines with something else
          lastChordLine = line.replaceAll('[', '|').replaceAll(']', '|');
          usedChords = false;
          break;

        // lyric lines
        case ' ':
          // print(lastChordLine);
          // print(line);

          // this is a lyric line
          // if we need to add chords, do a chordpro line merge with them
          if (lastChordLine.isNotEmpty && !usedChords) {
            var merged = chordProMerge(line: line, chords: lastChordLine);
            print('MERGED: $merged');
            converted.add(merged);
            usedChords = true;
          } else {
            converted.add(line.trim());
          }
          break;

        default:
      }
    }
    var retval = converted.join('\n').replaceAll(RegExp('\n\n+'), '\n\n');
    // print('CONVERSION COMPLETE:');
    // print(retval);
    return retval;
  }

  String chordProMerge({String line = '', String chords = ''}) {
    // lists are faster probably
    var lchars = line.trimRight().split('');
    var cchars = chords.trimRight().split('');

    // if one of the items is empty, return the other one
    if (chords.trim().isEmpty) return line.trim();
    if (line.trim().isEmpty) return '[${chords.trim()}]';

    // make sure the lyric characters match the length of the chord characters
    while (lchars.length < cchars.length) {
      lchars.add(' ');
    }

    // walk the chord line
    var merged = <String>[];
    String lchar, cchar;
    while (true) {
      // print('MERGED: ' + merged.join(''));

      // if there are no more chords, return the rest of the lyric line
      if (cchars.isEmpty) {
        merged.addAll(lchars);
        break;
      }

      cchar = cchars.removeAt(0);
      lchar = lchars.removeAt(0);
      var chord = <String>[];
      while (cchar != ' ') {
        // print('CCHAR: ' + cchar);
        chord.add(cchar);

        // also don't pop a space off the stack
        // or our comparison to the lyric line will get messed up
        if (cchars.isEmpty || cchars[0] == ' ') {
          break;
        } else {
          cchar = cchars.removeAt(0);
        }
      }

      if (chord.isNotEmpty) {
        merged.add('[');
        merged.addAll(chord);
        merged.add(']');

        // now add enough lyric characters to match the chord length
        merged.add(lchar);
        for (var i = 0; i < chord.length - 1; i++) {
          merged.add(lchars.removeAt(0));
        }
      } else {
        merged.add(lchar);
      }
    }
    // print(merged.join());
    return merged.join().trim();
  }
}

class OpenSongSet {
  String name = '';
  String path = '';
  Map<String, OpenSongSong> songs = {};

  OpenSongSet(this.path);

  void loadSet() {
    print('Loading set from $path');
    var fh = File(path);
    if (!fh.existsSync()) throw FileSystemException('Set File Not Found', path);
    var xml = fh.readAsStringSync();
    try {
      var doc = XmlDocument.parse(xml);
      var setData = doc.getElement('set');
      name = setData?.getAttribute('name') ?? '';

      // var groups = doc.getElement('slide_groups')?.findAllElements('slide_group') ?? [];
      var groups = doc.findAllElements('slide_group');
      for (var group in groups) {
        if (group.getAttribute('type') == 'song') {
          var songPath = group.getAttribute('path')! + group.getAttribute('name')!;
          var songFullPath = path.replaceFirst(RegExp(r'/Sets/.*'), '/Songs/$songPath');
          try {
            var song = OpenSongSong(songFullPath);
            songs[song.title] = song;
          } on SongInvalidDataException catch (e) {
            print(e.toString());
          } on FileSystemException catch (e) {
            print(e.toString());
          }
        }
      }
    } on XmlParserException {
      throw SetInvalidDataException(path);
    }
  }
}
