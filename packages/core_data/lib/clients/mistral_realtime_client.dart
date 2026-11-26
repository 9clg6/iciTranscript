import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:web_socket_channel/io.dart';

/// La clé Mistral est refusée (HTTP 401 ou `error` 401) : inutile de
/// réessayer avant que l'utilisateur la change.
class MistralKeyRejected implements Exception {
  /// Cree une instance de [MistralKeyRejected].
  const MistralKeyRejected();

  @override
  String toString() => 'MistralKeyRejected: clé Mistral refusée';
}

/// Moteur en ligne : Mistral Voxtral temps réel derrière l'interface de
/// [WebSocketClient], pour que la couche de fiabilité de la source distante
/// (tampon, fenêtres, pertes, reconnexion) reste la même.
///
/// Traduction du protocole (sonde réelle) :
/// - `connect` ouvre [url] avec `Authorization: Bearer`, envoie
///   `session.update` et attend `session.updated` ;
/// - `input_audio_buffer.append` devient `input_audio.append` ;
/// - `transcription.text.delta` devient `response.audio_transcript.delta` ;
/// - les phrases sont faites ici : un commit final (fin d'énoncé de la porte
///   de silence) rend un `response.audio_transcript.done` avec les deltas
///   reçus depuis le précédent, [doneQuiet] après le dernier delta (au plus
///   [doneAtMost] après le commit) ; le commit n'est jamais envoyé ;
/// - pendant une pause, du silence part au moins toutes les
///   [keepAliveEvery] (le serveur ferme après 30 s sans audio) ;
/// - `disconnect` envoie `input_audio.end` et attend `transcription.done` ;
///   la fermeture qui suit (1006) est la fin normale.
class MistralRealtimeClient extends WebSocketClient {
  /// Cree une instance de [MistralRealtimeClient].
  ///
  /// [apiKey] est lue à chaque connexion ; [transport] crée la socket brute
  /// à partir des en-têtes HTTP.
  MistralRealtimeClient({
    required Future<String?> Function() apiKey,
    required WebSocketClient Function(Map<String, String> headers) transport,
    this.targetStreamingDelayMs = defaultStreamingDelayMs,
    this.language,
  }) : _apiKey = apiKey,
       _transport = transport;

  /// Modèle temps réel.
  static const String model = 'voxtral-mini-transcribe-realtime-3-0';

  /// Adresse du service (l'URL locale passée à [connect] est ignorée).
  static const String url =
      'wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=$model';

  /// Délai de diffusion visé (ms) : le reste d'une phrase ~0,28 s après.
  static const int defaultStreamingDelayMs = 80;

  /// Silence envoyé au moins aussi souvent pendant une pause.
  static const Duration keepAliveEvery = Duration(seconds: 4);

  /// Calme après le dernier delta avant de rendre la phrase.
  static const Duration doneQuiet = Duration(milliseconds: 500);

  /// Au plus, après la fin d'énoncé.
  static const Duration doneAtMost = Duration(seconds: 3);
  static const Duration _endWait = Duration(seconds: 3);

  /// Transport réel : socket TLS avec les en-têtes HTTP donnés.
  static WebSocketClient defaultTransport(Map<String, String> headers) =>
      WebSocketClient(
        connectChannel: (Uri uri) =>
            IOWebSocketChannel.connect(uri, headers: headers),
      );

  /// Délai de diffusion demandé (ms).
  final int targetStreamingDelayMs;

  /// Langue imposée (code ISO), ou détection automatique si null.
  final String? language;
  final Future<String?> Function() _apiKey;
  final WebSocketClient Function(Map<String, String> headers) _transport;
  final Log _log = Log.named('MistralRealtimeClient');

  WebSocketClient? _raw;
  bool _ready = false;
  bool _ending = false;
  bool _rejected = false;
  // Clé refusée : la même n'est plus essayée (pas de tempête).
  String? _rejectedKey;
  StreamSubscription<String>? _messages;
  StreamSubscription<void>? _closes;
  Completer<void>? _sessionUpdated;
  Completer<void>? _finalDone;

  final StreamController<String> _out = StreamController<String>.broadcast();
  final StreamController<void> _closed = StreamController<void>.broadcast();

  // Deltas reçus depuis le dernier `done` rendu.
  final StringBuffer _text = StringBuffer();
  // Commits finaux dont le `done` n'est pas encore rendu.
  int _pendingDones = 0;
  Timer? _quiet;
  Timer? _cap;
  Timer? _keepAlive;
  // Secondes sans audio envoyé (comptées par le minuteur de maintien).
  int _quietSeconds = 0;
  // Octets PCM écrits sur la socket (maintien compris), lus par
  // [takeSentAudioMs] ; `connect` ne les remet pas à zéro (reconnexion).
  int _sentBytes = 0;

  @override
  Stream<String> get messageStream => _out.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  @override
  bool get isConnected => _ready && (_raw?.isConnected ?? false);

  @override
  Future<void> connect(String url) async {
    await _drop();
    final String? key = await _apiKey();
    if (key == null || key.isEmpty || key == _rejectedKey) {
      throw const MistralKeyRejected();
    }
    _rejected = false;
    final WebSocketClient raw = _transport(<String, String>{
      'Authorization': 'Bearer $key',
    })..handshakeTimeout = handshakeTimeout;
    _raw = raw;
    _ending = false;
    try {
      await raw.connect(MistralRealtimeClient.url);
    } on Exception catch (e) {
      _raw = null;
      // Le message peut recopier les en-têtes (donc la clé) : jamais
      // journalisé tel quel.
      if (e.toString().contains('401')) {
        _rejectedKey = key;
        _log.warning('Clé Mistral refusée (401)');
        throw const MistralKeyRejected();
      }
      _log.warning('Connexion Mistral impossible (${e.runtimeType})');
      throw const SocketException('Connexion Mistral impossible');
    }
    final Completer<void> updated = Completer<void>();
    _sessionUpdated = updated;
    _messages = raw.messageStream.listen(_onMessage);
    _closes = raw.onClosed.listen((_) => _onRawClosed(raw));
    raw.send(
      jsonEncode(<String, Object?>{
        'type': 'session.update',
        'session': <String, Object?>{
          'audio_format': <String, Object>{
            'encoding': 'pcm_s16le',
            'sample_rate': 16000,
          },
          'target_streaming_delay_ms': targetStreamingDelayMs,
          if (language != null) 'language': language,
        },
      }),
    );
    try {
      await updated.future.timeout(handshakeTimeout);
    } on TimeoutException {
      await _drop();
      rethrow;
    }
    if (_rejected) {
      _rejectedKey = key;
      await _drop();
      throw const MistralKeyRejected();
    }
    _ready = true;
    _quietSeconds = 0;
    _keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isConnected || _ending) return;
      if (++_quietSeconds >= keepAliveEvery.inSeconds) {
        _sendAudio(Uint8List(3200)); // 100 ms de silence
      }
    });
  }

  void _onMessage(String message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'session.updated':
        final Completer<void>? c = _sessionUpdated;
        if (c != null && !c.isCompleted) c.complete();
      case 'transcription.text.delta':
        final String text = decoded['text'] as String? ?? '';
        if (text.isEmpty) return;
        _text.write(text);
        _out.add(
          jsonEncode(<String, Object>{
            'type': 'response.audio_transcript.delta',
            'delta': text,
          }),
        );
        if (_pendingDones > 0) _armQuiet();
      case 'transcription.done':
        // Fin normale : rend ce qui reste, sans refaire les phrases déjà
        // rendues (le texte de ce `done` est la session entière).
        while (_pendingDones > 0) {
          _emitDone();
        }
        final Completer<void>? c = _finalDone;
        if (c != null && !c.isCompleted) c.complete();
      case 'error':
        final Object? error = decoded['error'];
        final Object? code = error is Map<String, dynamic>
            ? error['code']
            : null;
        if (code == 401 || code == '401') {
          _rejected = true;
          final Completer<void>? c = _sessionUpdated;
          if (c != null && !c.isCompleted) c.complete();
        }
        _log.warning('Erreur Mistral ($code)');
        final WebSocketClient? raw = _raw;
        if (raw != null) _onRawClosed(raw);
    }
  }

  void _onRawClosed(WebSocketClient raw) {
    if (!identical(_raw, raw)) return;
    final bool wasReady = _ready;
    _ready = false;
    _keepAlive?.cancel();
    final Completer<void>? done = _finalDone;
    if (done != null && !done.isCompleted) done.complete();
    // Après `input_audio.end`, la fermeture (1006) est la fin normale.
    if (_ending || !wasReady) return;
    if (!_closed.isClosed) _closed.add(null);
  }

  /// Un commit final : son `done` part [doneQuiet] après le dernier delta,
  /// au plus [doneAtMost] après le commit.
  void _onFinalCommit() {
    _pendingDones++;
    _armQuiet();
    _cap ??= Timer(doneAtMost, _emitDueDone);
  }

  void _armQuiet() {
    _quiet?.cancel();
    _quiet = Timer(doneQuiet, _emitDueDone);
  }

  void _emitDueDone() {
    if (_pendingDones == 0) return;
    _emitDone();
    if (_pendingDones > 0) {
      _armQuiet();
      _cap = Timer(doneAtMost, _emitDueDone);
    }
  }

  void _emitDone() {
    _quiet?.cancel();
    _cap?.cancel();
    _quiet = null;
    _cap = null;
    _pendingDones--;
    final String text = _text.toString();
    _text.clear();
    _out.add(
      jsonEncode(<String, Object>{
        'type': 'response.audio_transcript.done',
        'text': text,
      }),
    );
  }

  /// Audio réellement écrit sur la socket depuis le dernier appel (PCM16
  /// 16 kHz mono : 32 octets par ms), puis remise à zéro. Mistral facture
  /// cet audio.
  @override
  int takeSentAudioMs() {
    final int ms = _sentBytes ~/ 32;
    _sentBytes = 0;
    return ms;
  }

  void _sendAudio(Uint8List pcm) {
    _quietSeconds = 0;
    _sentBytes += pcm.length;
    _raw?.send(
      jsonEncode(<String, String>{
        'type': 'input_audio.append',
        'audio': base64Encode(pcm),
      }),
    );
  }

  @override
  void send(String message) {
    if (!isConnected) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'input_audio_buffer.append':
        final Object? audio = decoded['audio'];
        if (audio is String) _sentBytes += base64Decode(audio).length;
        _quietSeconds = 0;
        _raw?.send(
          jsonEncode(<String, Object?>{
            'type': 'input_audio.append',
            'audio': audio,
          }),
        );
      case 'input_audio_buffer.commit':
        if (decoded['final'] == true) _onFinalCommit();
    }
  }

  @override
  Future<void> disconnect() async {
    final WebSocketClient? raw = _raw;
    if (raw != null && isConnected) {
      _ending = true;
      final Completer<void> done = Completer<void>();
      _finalDone = done;
      raw.send('{"type":"input_audio.end"}');
      await done.future.timeout(_endWait, onTimeout: () {});
    }
    await _drop();
  }

  Future<void> _drop() async {
    _ready = false;
    _keepAlive?.cancel();
    _quiet?.cancel();
    _cap?.cancel();
    _quiet = null;
    _cap = null;
    _pendingDones = 0;
    _text.clear();
    final StreamSubscription<String>? m = _messages;
    final StreamSubscription<void>? c = _closes;
    _messages = null;
    _closes = null;
    // Sans attendre : sous fake_async, cancel() rend un futur de la zone
    // racine.
    unawaited(m?.cancel());
    unawaited(c?.cancel());
    final WebSocketClient? raw = _raw;
    _raw = null;
    if (raw != null) await raw.disconnect();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _out.close();
    await _closed.close();
  }
}
