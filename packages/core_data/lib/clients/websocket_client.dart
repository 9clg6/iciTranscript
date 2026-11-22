import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket configurable pour la communication avec voxmlx-serve.
///
/// Wrape [WebSocketChannel] et gere la connexion, la deconnexion, l'envoi et
/// la reception de messages. La reconnexion et le tampon de coupure sont
/// dans `TranscriptionRemoteDataSourceImpl`, qui lit [isConnected] avant
/// chaque envoi : il doit donc etre faux des que la socket est fermee.
class WebSocketClient {
  /// Cree une instance de [WebSocketClient].
  ///
  /// [connectChannel] ouvre le canal (injectable pour les tests).
  WebSocketClient({WebSocketChannel Function(Uri uri)? connectChannel})
    : _connectChannel = connectChannel ?? WebSocketChannel.connect;

  final WebSocketChannel Function(Uri uri) _connectChannel;
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
    final WebSocketChannel channel = _connectChannel(Uri.parse(url));
    // Un echec de connexion leve ici : le canal n'est jamais marque connecte.
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          _messageSubject.add(data);
        }
      },
      onError: (Object error) {
        if (identical(_channel, channel)) _channel = null;
        _messageSubject.addError(error);
      },
      onDone: () {
        if (identical(_channel, channel)) _channel = null;
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
