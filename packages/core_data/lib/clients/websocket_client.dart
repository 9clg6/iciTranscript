import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket configurable pour la communication avec voxmlx-serve.
///
/// Wrape [WebSocketChannel] et gere la connexion, la deconnexion,
/// la reconnexion, l'envoi et la reception de messages.
class WebSocketClient {
  /// Cree une instance de [WebSocketClient].
  WebSocketClient();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  // Les événements WebSocket ne représentent pas un état à rejouer. Un
  // BehaviorSubject réémettait le dernier `done` lors d'une nouvelle session,
  // ce qui pouvait finaliser à tort une phrase du nouvel appel.
  final PublishSubject<String> _messageSubject = PublishSubject<String>();

  /// Stream des messages recus depuis le serveur WebSocket.
  Stream<String> get messageStream => _messageSubject.stream;

  /// Indique si le client est connecte.
  bool get isConnected => _channel != null;

  /// Se connecte au serveur WebSocket a l'URL donnee.
  Future<void> connect(String url) async {
    await disconnect();
    final Uri uri = Uri.parse(url);
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    _subscription = _channel!.stream.listen(
      (dynamic data) {
        if (data is String) {
          _messageSubject.add(data);
        }
      },
      onError: (Object error) {
        _messageSubject.addError(error);
      },
      onDone: () {
        _channel = null;
      },
    );
  }

  /// Envoie un message au serveur WebSocket.
  void send(String message) {
    _channel?.sink.add(message);
  }

  /// Deconnecte du serveur WebSocket proprement.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// Libere les ressources.
  Future<void> dispose() async {
    await disconnect();
    await _messageSubject.close();
  }
}
