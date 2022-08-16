import 'dart:convert' as dc;

class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final bool error;
  String get json => dc.json.encode(toJson());

  const WebSocketMessage(this.type, [this.data = const {}, this.error = false]);
  factory WebSocketMessage.connected() => WebSocketMessage('connected');
  factory WebSocketMessage.disconnected() => WebSocketMessage('disconnected');
  factory WebSocketMessage.error(String msg) => WebSocketMessage('error', {'message': msg}, true);
  factory WebSocketMessage.text(String msg) => WebSocketMessage('text', {'text': msg}, true);

  WebSocketMessage.fromJson(Map data)
      : type = data['type'] ?? '',
        data = {...(data['data'] ?? {})},
        error = data['error'] ?? false;
  factory WebSocketMessage.fromString(String jsonString) {
    var data = dc.json.decode(jsonString);
    return WebSocketMessage.fromJson(data);
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': {...data},
        if (error) 'error': error,
      };
}
