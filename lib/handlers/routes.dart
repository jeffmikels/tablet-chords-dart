import 'dart:async';

import 'package:shelf/shelf.dart';

class DescribedOption {
  final String name;
  final String description;
  const DescribedOption(this.name, this.description);
}

class DescribedParam {
  final String name;
  final String description;
  final String type;
  final List<DescribedOption>? options;
  const DescribedParam(this.name, this.type, this.description, {this.options});
}

class DescribedRoute {
  final String path;
  final String description;
  final List<DescribedParam>? routeParams;
  final List<DescribedParam>? queryParams;
  final FutureOr<Response> Function(Request) handler;

  const DescribedRoute(
    this.path,
    this.description,
    this.handler, {
    this.routeParams,
    this.queryParams,
  });

  @override
  String toString() {
    var routeLines = <String>[];
    for (DescribedParam param in routeParams ?? []) {
      routeLines.add('${param.name} (${param.type}) ${param.description}');
      for (DescribedOption option in param.options ?? []) {
        routeLines.add('${option.name} : ${option.description}');
      }
    }
    var routeString = routeLines.isEmpty ? 'NONE' : routeLines.join('\n');

    var queryLines = <String>[];
    for (DescribedParam param in routeParams ?? []) {
      routeLines.add('${param.name} (${param.type}) ${param.description}');
      for (DescribedOption option in param.options ?? []) {
        routeLines.add('${option.name} : ${option.description}');
      }
    }
    var queryString = queryLines.isEmpty ? 'NONE' : routeLines.join('\n');

    return '''$path
  => $description
   Route Params: $routeString
   Query Params: $queryString''';
  }
}
