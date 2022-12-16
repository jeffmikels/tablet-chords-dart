import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../clients/client.dart';
import 'wsmessage.dart';

/// wrap a websocket channel into something more usable
class WebSocketClient {
  final WebSocketChannel _channel;
  WebSocketChannel get channel => _channel;

  WebSocketClient(WebSocketChannel channel) : _channel = channel;
  void send(WebSocketMessage msg) {
    _channel.sink.add(msg.json);
  }
}

class WebSocketManager {
  final List<WebSocketClient> clients = [];
  final Map<WebSocketClient, String> controllers = {};

  final SongsSetsClient songsSetsClient;

  final Map<String, String> keyMap = {}; // to remember websocket modified keys

  WebSocketManager(this.songsSetsClient);

  // WEBSOCKET FUNCTIONS
  void onConnect(WebSocketChannel channel) {
    var client = WebSocketClient(channel);
    print('Connected!');
    clients.add(client);
    client.send(WebSocketMessage.connected());
    channel.stream.listen((message) {
      onMessage(client, message);
    }, onDone: () => onDone(client));
  }

  void onDone(WebSocketClient client) {
    clients.remove(client);
  }

  void onMessage(WebSocketClient sender, String message) {
    late WebSocketMessage ws;
    try {
      ws = WebSocketMessage.fromString(message);
    } on JsonUnsupportedObjectError catch (e) {
      print(e);
      sender.send(WebSocketMessage.error('Could not parse incoming WS message.'));
      return;
    }
    print(ws.json);
    switch (ws.type) {
      case 'alert':
        broadcast(ws, ignoreClients: [sender]);
        break;
      case 'control':
        var toControl = ws.data['set'];
        if (toControl != null) {
          // remove previous controllers
          var toRemove = [];
          for (var client in controllers.keys) {
            if (controllers[client] == toControl) {
              client.send(WebSocketMessage('control-stopped', {'set': toControl}));
              toRemove.add(client);
            }
          }
          for (var client in toRemove) {
            controllers.remove(client);
          }
          controllers[sender] = toControl;
          sender.send(WebSocketMessage('control-allow', {'set': toControl}));
        } else {
          sender.send(WebSocketMessage.error('INVALID CONTROL REQUEST'));
        }
        break;
      case 'key':
        var toControlSet = ws.data['set'];
        var toControlSong = ws.data['song'];
        var toControlKey = ws.data['key'];
        if (toControlSet != null && toControlSong != null && toControlKey != null) {
          if (controllers[sender] == toControlSet) {
            broadcast(ws, ignoreClients: [sender]);
          } else {
            sender.send(WebSocketMessage.error('YOU ARE NOT A CONTROLLER FOR THIS SET'));
          }
        } else {
          sender.send(WebSocketMessage.error('INVALID KEY MESSAGE RECEIVED'));
        }
        break;
      default:
        sender.send(WebSocketMessage.error('MESSAGE TYPE UNKNOWN'));
    }
  }

  void broadcast(WebSocketMessage msg, {List<WebSocketClient> ignoreClients = const []}) {
    for (var client in clients) {
      if (ignoreClients.contains(client)) continue;
      client.send(msg);
    }
  }
}
