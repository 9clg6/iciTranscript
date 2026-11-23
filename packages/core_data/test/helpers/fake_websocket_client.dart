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

  /// Heure (horloge du test) de chaque connexion établie.
  final List<Duration> connectionOpenedAt = <Duration>[];

  /// Messages reçus, connexion par connexion.
  final List<List<String>> connectionMessages = <List<String>>[];

  /// Si non nul, le serveur répond seul à chaque commit final par un
  /// `done` ([autoDoneText]) après ce délai, si la connexion vit encore.
  Duration? autoDoneAfter;
  String autoDoneText = 'phrase';

  /// Faux : la poignée de main ne se termine jamais (connect sans fin).
  bool hangConnect = false;

  /// Serveur chargé : la poignée de main aboutit après ce délai. Une
  /// tentative remplacée entre-temps (nouvel appel à [connect] ou
  /// [disconnect]) n'aboutit pas, comme un canal abandonné.
  Duration acceptDelay = Duration.zero;
  int _attempt = 0;

  /// Appelé à chaque commit final reçu : numéros des chunks de la phrase et
  /// génération de la connexion (voir [emitIfAlive]). Pour un serveur
  /// factice piloté par le test (file séquentielle, blocages).
  void Function(List<int> utteranceIds, int generation)? onFinalCommit;

  // Audio envoyé sans `done` sur la connexion courante : phrases commitées
  // en attente (numéros des chunks) et phrase en cours.
  final List<List<int>> _pendingUtterances = <List<int>>[];
  List<int> _currentUtterance = <int>[];
  int _generation = 0;

  /// Génération de la connexion courante (change à chaque connexion ou
  /// fermeture).
  int get generation => _generation;

  /// Chunks transcrits : acquittés par un `done` sur la connexion qui les a
  /// reçus, dans l'ordre d'acquittement.
  final List<int> transcribedOrder = <int>[];
  final Set<int> transcribedIds = <int>{};
  final List<int> transcribedTwice = <int>[];

  // Fermetures vues par le client (canal fini ou en erreur), sans appel à
  // disconnect().
  final StreamController<void> _closes = StreamController<void>.broadcast();

  /// Le canal s'est fermé côté serveur.
  @override
  Stream<void> get onClosed => _closes.stream;

  /// Plus grand volume d'audio (en chunks de 100 ms) envoyé et pas encore
  /// acquitté par un `done`, sur une même connexion.
  int maxInFlightChunks = 0;

  int get inFlightChunks =>
      _pendingUtterances.fold<int>(0, (int a, List<int> b) => a + b.length) +
      _currentUtterance.length;

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
    if (hangConnect) return Completer<void>().future;
    final int attempt = ++_attempt;
    if (acceptDelay > Duration.zero) {
      await Future<void>.delayed(acceptDelay);
      if (attempt != _attempt) return; // remplacée : jamais connectée
    }
    if (!accepting) {
      throw const SocketException('Connection refused');
    }
    _connected = true;
    final Duration? openedAt = now?.call();
    if (openedAt != null) connectionOpenedAt.add(openedAt);
    _generation++;
    _pendingUtterances.clear();
    _currentUtterance = <int>[];
    connections.add(<int>[]);
    connectionMessages.add(<String>[]);
  }

  /// La socket se ferme côté serveur (crash, redémarrage). Avec [notify],
  /// le client le voit comme le vrai (fin du canal, [onClosed]) ; sans, la
  /// fermeture passe inaperçue jusqu'au prochain envoi.
  void drop({bool notify = true}) {
    if (!_connected) return;
    _connected = false;
    _generation++;
    if (notify) _closes.add(null);
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
      _currentUtterance.add(id);
      if (inFlightChunks > maxInFlightChunks) {
        maxInFlightChunks = inFlightChunks;
      }
    } else if (json['type'] == 'input_audio_buffer.commit' &&
        json['final'] == true) {
      final List<int> utterance = _currentUtterance;
      _pendingUtterances.add(utterance);
      _currentUtterance = <int>[];
      onFinalCommit?.call(List<int>.of(utterance), _generation);
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
      for (final int id in _pendingUtterances.removeAt(0)) {
        transcribedOrder.add(id);
        if (!transcribedIds.add(id)) transcribedTwice.add(id);
      }
    }
    _messages.add(jsonEncode(event));
  }

  /// [emit] si la connexion de [generation] vit encore.
  void emitIfAlive(int generation, Map<String, Object> event) {
    if (_connected && generation == _generation) emit(event);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _generation++;
    _attempt++;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _messages.close();
    await _closes.close();
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
