import 'dart:async';

import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:rxdart/rxdart.dart';

/// Une socket de la source distante, routée par l'adresse de connexion :
/// [MistralRealtimeClient.url] → [mistral], toute autre → [local]. Le choix
/// du moteur est fait une fois, par l'adresse que le service passe ; la
/// couche de fiabilité ne voit qu'un client.
class EngineRoutingClient extends WebSocketClient {
  /// Cree une instance de [EngineRoutingClient].
  EngineRoutingClient({required this.local, required this.mistral});

  /// voxmlx sur ce Mac.
  final WebSocketClient local;

  /// Mistral en ligne.
  final WebSocketClient mistral;

  WebSocketClient _active = _none;
  static final WebSocketClient _none = WebSocketClient();

  @override
  Stream<String> get messageStream =>
      Rx.merge(<Stream<String>>[local.messageStream, mistral.messageStream]);

  @override
  Stream<void> get onClosed => Rx.merge(<Stream<void>>[
    local.onClosed.where((_) => identical(_active, local)),
    mistral.onClosed.where((_) => identical(_active, mistral)),
  ]);

  @override
  bool get isConnected => _active.isConnected;

  @override
  Future<void> connect(String url) async {
    final WebSocketClient next = url == MistralRealtimeClient.url
        ? mistral
        : local;
    if (!identical(next, _active)) await _active.disconnect();
    _active = next;
    next.handshakeTimeout = handshakeTimeout;
    await next.connect(url);
  }

  @override
  void send(String message) => _active.send(message);

  @override
  Future<void> disconnect() => _active.disconnect();

  @override
  Future<void> dispose() async {
    await local.dispose();
    await mistral.dispose();
  }
}
