import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';

/// Socket factice, sans réseau, pilotable par le test.
///
/// Comme le vrai client : une fois la socket fermée côté serveur,
/// [isConnected] devient faux et [send] jette le message en silence. Une
/// perte de données se voit donc dans [appendedChunkIds].
///
/// `extends` (et non `implements`) pour rester compilable si le vrai client
/// gagne des membres.
final class FakeWebSocketClient extends WebSocketClient {
  FakeWebSocketClient({this.now});

  /// Horloge du test (fake_async), pour dater les tentatives de connexion.
  final Duration Function()? now;

  /// Faux : le serveur refuse les connexions (serveur tombé, port fermé).
  bool accepting = true;

  bool _connected = false;
  int connectCalls = 0;
  final List<Duration> connectAttempts = <Duration>[];

  /// Messages reçus par le serveur, dans l'ordre, toutes connexions confondues.
  final List<String> received = <String>[];

  /// Numéro de chaque chunk audio reçu (voir [chunk]), dans l'ordre.
  final List<int> appendedChunkIds = <int>[];

  /// Numéros reçus, connexion par connexion.
  final List<List<int>> connections = <List<int>>[];

  /// Messages reçus, connexion par connexion.
  final List<List<String>> connectionMessages = <List<String>>[];

  /// Si non nul, le serveur répond seul à chaque commit final par un
  /// `done` ([autoDoneText]) après ce délai, si la connexion vit encore.
  Duration? autoDoneAfter;
  String autoDoneText = 'phrase';

  // Audio envoyé sans `done` sur la connexion courante : phrases commitées
  // en attente (taille en chunks) et phrase en cours.
  final List<int> _pendingUtterances = <int>[];
  int _currentUtterance = 0;
  int _generation = 0;

  /// Plus grand volume d'audio (en chunks de 100 ms) envoyé et pas encore
  /// acquitté par un `done`, sur une même connexion.
  int maxInFlightChunks = 0;

  int get inFlightChunks =>
      _pendingUtterances.fold<int>(0, (int a, int b) => a + b) +
      _currentUtterance;

  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    connectCalls++;
    final Duration? at = now?.call();
    if (at != null) connectAttempts.add(at);
    if (!accepting) {
      throw const SocketException('Connection refused');
    }
    _connected = true;
    _generation++;
    _pendingUtterances.clear();
    _currentUtterance = 0;
    connections.add(<int>[]);
    connectionMessages.add(<String>[]);
  }

  /// La socket se ferme côté serveur (crash, redémarrage).
  void drop() {
    _connected = false;
    _generation++;
  }

  @override
  void send(String message) {
    if (!_connected) return;
    received.add(message);
    connectionMessages.last.add(message);
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      final int id = chunkIdOf(json['audio'] as String);
      appendedChunkIds.add(id);
      connections.last.add(id);
      _currentUtterance++;
      if (inFlightChunks > maxInFlightChunks) {
        maxInFlightChunks = inFlightChunks;
      }
    } else if (json['type'] == 'input_audio_buffer.commit' &&
        json['final'] == true) {
      _pendingUtterances.add(_currentUtterance);
      _currentUtterance = 0;
      final Duration? delay = autoDoneAfter;
      if (delay == null) return;
      final int generation = _generation;
      Timer(delay, () {
        if (!_connected || generation != _generation) return;
        emit(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': autoDoneText,
        });
      });
    }
  }

  /// Le serveur envoie un événement au client. Un `done` acquitte la plus
  /// ancienne phrase commitée de la connexion.
  void emit(Map<String, Object> event) {
    if (event['type'] == 'response.audio_transcript.done' &&
        _pendingUtterances.isNotEmpty) {
      _pendingUtterances.removeAt(0);
    }
    _messages.add(jsonEncode(event));
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _generation++;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _messages.close();
  }
}

/// Types des messages reçus ('input_audio_buffer.append', '…commit').
List<String> messageTypes(List<String> messages) => messages
    .map(
      (String message) =>
          (jsonDecode(message) as Map<String, dynamic>)['type'] as String,
    )
    .toList();

/// Chunk PCM16 de 100 ms (1600 échantillons) portant son numéro [id] dans
/// ses deux premiers échantillons. Voisé : amplitude 1200 (RMS bien au-dessus
/// du seuil de parole). Non voisé : zéros (au plus deux échantillons forts,
/// sous le minimum de trois exigé par la porte de silence).
AudioChunk chunk(
  AudioSource source,
  int id, {
  required int timestampMs,
  bool voiced = true,
}) {
  final Uint8List data = Uint8List(3200);
  final ByteData samples = ByteData.sublistView(data);
  if (voiced) {
    for (int offset = 4; offset < data.length; offset += 2) {
      samples.setInt16(offset, 1200, Endian.little);
    }
  }
  samples.setInt16(0, id & 0x7FFF, Endian.little);
  samples.setInt16(2, id >> 15, Endian.little);
  return AudioChunk(source: source, data: data, timestampMs: timestampMs);
}

/// Relit le numéro d'un chunk depuis son payload base64.
int chunkIdOf(String base64Audio) {
  final ByteData samples = ByteData.sublistView(
    base64Decode(base64Audio.substring(0, 8)),
  );
  return samples.getInt16(0, Endian.little) +
      (samples.getInt16(2, Endian.little) << 15);
}
