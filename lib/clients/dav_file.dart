/// copied from https://github.com/timestee/dart-webdav
///
import 'package:xml/xml.dart' as xml;

class FileInfo {
  String path;
  String size;
  String modificationTime;
  DateTime creationTime;
  String contentType;

  DateTime get modified {
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var match = RegExp(r'.*?, (\d+) (.*?) (\d+) (\d+):(\d+):(\d+)').firstMatch(modificationTime);
    if (match == null) return creationTime;

    var day = int.parse(match.group(1)!);
    var mon = months.indexOf(match.group(2)!) + 1;
    var year = int.parse(match.group(3)!);
    var h = int.parse(match.group(4)!);
    var m = int.parse(match.group(5)!);
    var s = int.parse(match.group(6)!);
    return DateTime(year, mon, day, h, m, s);
  }

  String get basename => path.split('/').last;

  FileInfo(this.path, this.size, this.modificationTime, this.creationTime, this.contentType);

  // Returns the decoded name of the file / folder without the whole path
  String get name {
    if (isDirectory) {
      return Uri.decodeFull(path.substring(0, path.lastIndexOf("/")).split("/").last);
    }

    return Uri.decodeFull(path.split("/").last);
  }

  bool get isDirectory => path.endsWith("/");

  @override
  String toString() {
    return 'FileInfo{name: $name, isDirectory: $isDirectory ,path: $path, size: $size, modificationTime: $modificationTime, creationTime: $creationTime, contentType: $contentType}';
  }
}

/// get filed [name] from the property node
String? prop(dynamic prop, String name, [String? defaultVal]) {
  if (prop is Map) {
    final val = prop['D:$name'];
    if (val == null) {
      return defaultVal;
    }
    return val;
  }
  return defaultVal;
}

List<FileInfo> treeFromWebDavXml(String xmlStr) {
  // Initialize a list to store the FileInfo Objects
  List<FileInfo> tree = List.empty(growable: true);

  // parse the xml using the xml.parse method
  var xmlDocument = xml.XmlDocument.parse(xmlStr);

  // Iterate over the response to find all folders / files and parse the information
  findAllElementsFromDocument(xmlDocument, "response").forEach((response) {
    var davItemName = findElementsFromElement(response, "href").single.text;
    findElementsFromElement(findElementsFromElement(response, "propstat").first, "prop").forEach((element) {
      final contentLengthElements = findElementsFromElement(element, "getcontentlength");
      final contentLength = contentLengthElements.isNotEmpty ? contentLengthElements.single.text : "";

      final lastModifiedElements = findElementsFromElement(element, "getlastmodified");
      final lastModified = lastModifiedElements.isNotEmpty ? lastModifiedElements.single.text : "";

      final creationTimeElements = findElementsFromElement(element, "creationdate");
      final creationTime = creationTimeElements.isNotEmpty
          ? creationTimeElements.single.text
          : DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();

      // Add the just found file to the tree
      tree.add(FileInfo(davItemName, contentLength, lastModified, DateTime.parse(creationTime), ""));
    });
  });
  // Return the tree
  return tree;
}

List<xml.XmlElement> findAllElementsFromDocument(xml.XmlDocument document, String tag) =>
    document.findAllElements(tag, namespace: '*').toList();

List<xml.XmlElement> findElementsFromElement(xml.XmlElement element, String tag) =>
    element.findElements(tag, namespace: '*').toList();
