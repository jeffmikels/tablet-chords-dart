import 'dart:async';

import 'package:shelf/shelf.dart';

class DescribedParam {
  final String name;
  final String description;
  final String type;
  const DescribedParam(this.name, this.type, this.description);
}

class DescribedRoute {
  final String path;
  final String description;
  final List<DescribedParam>? params;
  final FutureOr<Response> Function(Request) handler;

  const DescribedRoute(this.path, this.description, this.handler, {this.params});
}
