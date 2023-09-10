import 'package:hotreloader/hotreloader.dart';

import './server.dart' as server;

Future<void> main(List<String> args) async {
  // instantiate a reloader that by monitors the project's source code folders for changes
  final reloader = await HotReloader.create();

  server.main(args);

  // cleanup
  reloader.stop();
}
