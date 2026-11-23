import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket configurable pour la communication avec voxmlx-serve.
///
/// Wrape [WebSocketChannel] et gere la connexion, la deconnexion, l'envoi et
/// la reception de messages. La reconnexion et le tampon de coupure sont
/// dans `TranscriptionRemoteDataSourceImpl`, qui lit [isConnected] avant
/// chaque envoi et écoute [onClosed] : une fermeture côté serveur doit se
/// voir même quand rien n'est à envoyer (sonde 2 : rattrapage en attente).
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

  final StreamController<void> _closedController =
      StreamController<void>.broadcast();

  /// Le canal s'est fermé ou a échoué côté serveur (pas après [disconnect]).
  Stream<void> get onClosed => _closedController.stream;

  /// Poignée de main au-delà de laquelle [connect] échoue (sonde 2 : une
  /// reconnexion est restée 30 s bloquée sur `ready`).
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Borne de la prochaine poignée de main ; la source distante et le
  /// rattrapage l'allongent quand un serveur chargé accepte lentement.
  Duration handshakeTimeout = connectTimeout;

  /// Borne adaptative (seul endroit) : 10 s, doublée à chaque poignée de
  /// main expirée de suite ([slowAccepts]), au plus 60 s.
  static Duration handshakeBound(int slowAccepts) {
    final Duration bound =
        connectTimeout * (1 << (slowAccepts < 3 ? slowAccepts : 3));
    return bound > maxHandshake ? maxHandshake : bound;
  }

  /// Plus longue poignée de main attendue.
  static const Duration maxHandshake = Duration(seconds: 60);

  /// Indique si le client est connecte.
  bool get isConnected => _channel != null;

  /// Se connecte au serveur WebSocket a l'URL donnee.
  Future<void> connect(String url) async {
    await disconnect();
    final WebSocketChannel channel = _connectChannel(Uri.parse(url));
    // Un echec de connexion leve ici : le canal n'est jamais marque connecte.
    try {
      await channel.ready.timeout(handshakeTimeout);
    } on TimeoutException {
      unawaited(channel.sink.close().catchError((Object _) {}));
      rethrow;
    }
    _channel = channel;
    void closedByServer() {
      if (!identical(_channel, channel)) return;
      _channel = null;
      if (!_closedController.isClosed) _closedController.add(null);
    }

    _subscription = channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          _messageSubject.add(data);
        }
      },
      onError: (Object error) {
        closedByServer();
        _messageSubject.addError(error);
      },
      onDone: closedByServer,
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
    await _closedController.close();
  }
}
