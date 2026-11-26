import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';

/// Faux service Mistral temps réel, sans réseau : le test joue le serveur
/// (deltas à la main). Protocole de la sonde réelle
/// (packages/core_data/test/fixtures/mistral_probe.dart) : `session.update`
/// → `session.updated` ; après `input_audio.end`, `transcription.done`
/// 793 ms plus tard puis fermeture sans trame (1006) 2093 ms après.
final class FakeMistralServer {
  /// Clé refusée : chaque poignée de main échoue en HTTP 401.
  bool refuseKey = false;

  /// Poignées de main tentées.
  int handshakes = 0;

  /// Appelé à la réception de `input_audio.end` (avant le `done`).
  void Function(FakeMistralSocket socket)? onEnd;

  final List<FakeMistralSocket> sockets = <FakeMistralSocket>[];

  /// Octets d'audio reçus par `input_audio.append` (maintien compris), sur
  /// toutes les sockets : ce que Mistral facture.
  int appendedBytes = 0;

  /// [appendedBytes] en ms (PCM16 mono 16 kHz).
  int get appendedMs => appendedBytes ~/ 32;

  /// Dernière socket créée (celle du micro quand le son du Mac est coupé).
  FakeMistralSocket get live => sockets.last;

  WebSocketClient transport(Map<String, String> headers) {
    final FakeMistralSocket socket = FakeMistralSocket(this);
    sockets.add(socket);
    return socket;
  }
}

final class FakeMistralSocket extends WebSocketClient {
  FakeMistralSocket(this._server);

  final FakeMistralServer _server;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<void> _closed = StreamController<void>.broadcast();
  final StringBuffer _said = StringBuffer();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  /// Le serveur envoie [event].
  void push(Map<String, Object?> event) {
    if (_connected) _messages.add(jsonEncode(event));
  }

  /// Un `transcription.text.delta`.
  void delta(String text) {
    _said.write(text);
    push(<String, Object?>{'type': 'transcription.text.delta', 'text': text});
  }

  /// Fermeture côté serveur ou réseau (1006).
  void close() {
    if (!_connected) return;
    _connected = false;
    _closed.add(null);
  }

  /// La clé est révoquée en pleine session : `error` 401, puis fermeture.
  void rejectKey() {
    push(<String, Object?>{
      'type': 'error',
      'error': <String, Object?>{'code': 401, 'message': 'Unauthorized'},
    });
    close();
  }

  @override
  Future<void> connect(String url) async {
    _server.handshakes++;
    if (_server.refuseKey) {
      throw WebSocketException(
        "Connection to '$url' was not upgraded to websocket, HTTP status "
        'code: 401',
      );
    }
    _connected = true;
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    switch (json['type']) {
      case 'session.update':
        scheduleMicrotask(
          () => push(<String, Object?>{
            'type': 'session.updated',
            'session': json['session'],
          }),
        );
      case 'input_audio.append':
        _server.appendedBytes += base64Decode(json['audio'] as String).length;
      case 'input_audio.end':
        _server.onEnd?.call(this);
        Timer(const Duration(milliseconds: 793), () {
          push(<String, Object?>{
            'type': 'transcription.done',
            'text': _said.toString(),
            'segments': <Object>[],
            'language': null,
          });
          Timer(const Duration(milliseconds: 2093), close);
        });
    }
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> dispose() async => _connected = false;
}

/// Vraie source distante sur deux vrais [MistralRealtimeClient] branchés
/// sur [server] (jamais l'API réelle).
TranscriptionRemoteDataSourceImpl mistralRemote(
  FakeMistralServer server, {
  String key = 'mistral-test-SECRET-0123456789',
}) => TranscriptionRemoteDataSourceImpl(
  micClient: MistralRealtimeClient(
    apiKey: () async => key,
    transport: server.transport,
  ),
  systemClient: MistralRealtimeClient(
    apiKey: () async => key,
    transport: FakeMistralServer().transport,
  ),
);
