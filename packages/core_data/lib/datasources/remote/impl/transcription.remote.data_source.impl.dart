import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:rxdart/rxdart.dart';

/// Implementation WebSocket avec DEUX flux séparés (Path A) :
/// - micro (input) → transcript "MOI"
/// - audio système (output) → transcript des interlocuteurs distants
///
/// voxmlx-serve gère une session indépendante par connexion WebSocket, donc on
/// ouvre deux connexions vers le même serveur. Aucun mixage : chaque source est
/// transcrite séparément et taguée correctement.
///
/// Une socket qui tombe ne perd pas l'audio : il est gardé dans l'ordre
/// (au plus [_maxBufferedMs] par source), la socket est rouverte avec un
/// délai croissant, puis le tampon part avant l'audio en direct. Au-delà de
/// la borne, le plus ancien est jeté et signalé par [audioGaps].
final class TranscriptionRemoteDataSourceImpl
    implements TranscriptionRemoteDataSource {
  /// Cree une instance de [TranscriptionRemoteDataSourceImpl].
  TranscriptionRemoteDataSourceImpl({
    WebSocketClient? micClient,
    WebSocketClient? systemClient,
  }) : _mic = micClient ?? WebSocketClient(),
       _sys = systemClient ?? WebSocketClient();

  final WebSocketClient _mic;
  final WebSocketClient _sys;
  bool _systemConnected = false;
  String _url = 'ws://localhost:8000/v1/realtime';

  // Gate de silence (VAD simple) : chaque source possède son propre tour de
  // parole. Une pause finalise explicitement la session voxmlx correspondante,
  // ce qui borne les caches du modèle et évite la dérive sur les appels longs.
  static const int _voiceThreshold = 350; // amplitude int16 ~ parole
  static const double _voiceStartRms = 300;
  static const double _voiceContinueRms = 180;
  // Une respiration au milieu d'une phrase dépasse souvent 0,7 s : en dessous
  // de ~1,2 s, une même phrase était coupée en plusieurs lignes.
  static const int _silenceToFinalizeMs = 1200;
  static const int _maxUtteranceMs = 30000;
  // Une phrase restée moins longtemps au-dessus du seuil de parole est
  // marquée sans parole (UtteranceWindow.hadSpeech) : filtre d'hallucinations.
  static const int _minSpeechMs = 300;
  // PCM16 mono 16 kHz.
  static const int _bytesPerMs = 32;

  // Coupure : au moins 120 s d'audio gardées par source, reconnexion de
  // 0,5 s à 10 s au plus (la reprise suit vite le retour du serveur).
  static const int _maxBufferedMs = 120000;
  static const Duration _firstRetryDelay = Duration(milliseconds: 500);
  static const Duration _maxRetryDelay = Duration(seconds: 10);
  final Map<AudioSource, _Outage?> _outages = <AudioSource, _Outage?>{
    AudioSource.input: null,
    AudioSource.output: null,
  };
  final PublishSubject<AudioGap> _gapSubject = PublishSubject<AudioGap>();
  final Map<AudioSource, int> _voicedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, int> _lastVoicedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, int> _utteranceStartedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, bool> _utteranceActive = <AudioSource, bool>{
    AudioSource.input: false,
    AudioSource.output: false,
  };
  // Intervalles des phrases dont le commit final est parti sur la socket
  // vivante, dans l'ordre des `done` attendus.
  final Map<AudioSource, Queue<UtteranceWindow>> _pendingWindows =
      <AudioSource, Queue<UtteranceWindow>>{
        AudioSource.input: Queue<UtteranceWindow>(),
        AudioSource.output: Queue<UtteranceWindow>(),
      };
  final Expando<UtteranceWindow> _eventWindows = Expando<UtteranceWindow>();

  final BehaviorSubject<domain.ConnectionState> _connectionStateSubject =
      BehaviorSubject<domain.ConnectionState>.seeded(
        domain.ConnectionState.disconnected,
      );

  @override
  Future<void> connect({
    String url = 'ws://localhost:8000/v1/realtime',
    bool systemAudioEnabled = true,
  }) async {
    _connectionStateSubject.add(domain.ConnectionState.connecting);
    _url = url;
    _systemConnected = systemAudioEnabled;
    _clearOutages();
    _resetUtteranceState();
    try {
      await Future.wait(<Future<void>>[
        _mic.connect(url),
        if (systemAudioEnabled) _sys.connect(url) else _sys.disconnect(),
      ]);
      _connectionStateSubject.add(domain.ConnectionState.connected);
    } catch (_) {
      await Future.wait(<Future<void>>[_mic.disconnect(), _sys.disconnect()]);
      _connectionStateSubject.add(domain.ConnectionState.error);
      rethrow;
    }
  }

  @override
  void sendAudio(AudioChunk chunk) {
    final AudioSource source = chunk.source;
    if (source == AudioSource.output && !_systemConnected) return;
    final int now = chunk.timestampMs;
    final bool voiced = _isVoiced(
      chunk.data,
      alreadyActive: _utteranceActive[source]!,
    );

    if (voiced) {
      if (!_utteranceActive[source]!) {
        _utteranceActive[source] = true;
        _utteranceStartedMs[source] = now;
        _voicedMs[source] = 0;
      }
      _lastVoicedMs[source] = now;
      _voicedMs[source] = _voicedMs[source]! + chunk.data.length ~/ _bytesPerMs;
      _sendChunk(chunk);

      // Même sans pause, borner une session évite que l'état incrémental du
      // modèle dérive après plusieurs minutes (langue parasite / ponctuation).
      if (now - _utteranceStartedMs[source]! >= _maxUtteranceMs) {
        _finalizeSource(source);
      }
      return;
    }

    if (!_utteranceActive[source]!) {
      return;
    }

    // Conserver une courte queue de silence pour ne pas couper la fin du mot.
    if (now - _lastVoicedMs[source]! <= _silenceToFinalizeMs) {
      _sendChunk(chunk);
      return;
    }

    _finalizeSource(source);
  }

  void _sendChunk(AudioChunk chunk) {
    _send(
      chunk.source,
      jsonEncode(<String, String>{
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk.data),
      }),
      timestampMs: chunk.timestampMs,
      audioMs: chunk.data.length ~/ _bytesPerMs,
    );
  }

  WebSocketClient _client(AudioSource source) =>
      source == AudioSource.input ? _mic : _sys;

  /// Envoie [message] sur la socket de [source], ou le garde dans le tampon
  /// de coupure, dans l'ordre. [window] est attendue en retour d'un `done`
  /// une fois le commit final réellement écrit sur une socket vivante.
  void _send(
    AudioSource source,
    String message, {
    int? timestampMs,
    int audioMs = 0,
    UtteranceWindow? window,
  }) {
    final WebSocketClient client = _client(source);
    final _Outage? outage = _outages[source];
    if (outage == null && client.isConnected) {
      client.send(message);
      if (window != null) _pendingWindows[source]!.add(window);
      return;
    }
    (outage ?? _startOutage(source)).add(
      _Outgoing(message, timestampMs, audioMs, window),
    );
  }

  _Outage _startOutage(AudioSource source) {
    // Les phrases commitées sur la socket morte n'auront jamais de `done`.
    _pendingWindows[source]!.clear();
    final _Outage outage = _Outage(_maxBufferedMs);
    _outages[source] = outage;
    _connectionStateSubject.add(domain.ConnectionState.connecting);
    _scheduleReconnect(source, outage);
    return outage;
  }

  void _scheduleReconnect(AudioSource source, _Outage outage) {
    final Duration delay =
        _firstRetryDelay * (1 << math.min(outage.attempts, 5));
    outage.retry = Timer(
      delay > _maxRetryDelay ? _maxRetryDelay : delay,
      () => unawaited(_reconnect(source, outage)),
    );
  }

  Future<void> _reconnect(AudioSource source, _Outage outage) async {
    outage.attempts++;
    final WebSocketClient client = _client(source);
    try {
      await client.connect(_url);
    } catch (_) {
      if (identical(_outages[source], outage)) {
        _scheduleReconnect(source, outage);
      }
      return;
    }
    // Session close ou relancée pendant la connexion.
    if (!identical(_outages[source], outage)) return;

    while (outage.queue.isNotEmpty && client.isConnected) {
      final _Outgoing item = outage.queue.removeFirst();
      outage.bufferedMs -= item.audioMs;
      client.send(item.message);
      if (item.window != null) _pendingWindows[source]!.add(item.window!);
    }
    if (outage.queue.isNotEmpty) {
      // Retombée pendant le renvoi : le reste attend la prochaine socket.
      _pendingWindows[source]!.clear();
      _scheduleReconnect(source, outage);
      return;
    }
    _outages[source] = null;
    _emitGap(source, outage);
    if (_outages.values.every((_Outage? o) => o == null)) {
      _connectionStateSubject.add(domain.ConnectionState.connected);
    }
  }

  void _emitGap(AudioSource source, _Outage outage) {
    final int? start = outage.lostStartMs;
    if (start == null) return;
    _gapSubject.add(
      AudioGap(source: source, startMs: start, endMs: outage.lostEndMs!),
    );
  }

  /// Ferme les coupures en cours ; l'audio encore en tampon est perdu pour
  /// la transcription (il reste dans le WAV) et signalé comme tel.
  void _clearOutages() {
    for (final AudioSource source in AudioSource.values) {
      final _Outage? outage = _outages[source];
      if (outage == null) continue;
      outage.retry?.cancel();
      outage.loseAll();
      _outages[source] = null;
      _emitGap(source, outage);
    }
  }

  /// Audio en attente d'envoi pour [source] (zéro hors coupure).
  Duration bufferedAudio(AudioSource source) =>
      Duration(milliseconds: _outages[source]?.bufferedMs ?? 0);

  @override
  Stream<AudioGap> get audioGaps => _gapSubject.stream;

  bool _isVoiced(Uint8List data, {required bool alreadyActive}) {
    final ByteData bd = ByteData.sublistView(data);
    int sampleCount = 0;
    int loudSampleCount = 0;
    double sumSquares = 0;
    for (int i = 0; i + 1 < data.length; i += 2) {
      final int sample = bd.getInt16(i, Endian.little);
      sampleCount++;
      if (sample.abs() > _voiceThreshold) loudSampleCount++;
      sumSquares += sample * sample;
    }
    if (sampleCount == 0) return false;

    // Un clic isolé ne doit pas maintenir Voxtral actif. L'hystérésis garde
    // toutefois les fins de mots plus faibles une fois la parole détectée.
    final int minimumLoudSamples = math.max(3, sampleCount ~/ 50);
    if (loudSampleCount < minimumLoudSamples) return false;
    final double rms = math.sqrt(sumSquares / sampleCount);
    return rms >= (alreadyActive ? _voiceContinueRms : _voiceStartRms);
  }

  @override
  Set<AudioSource> sendCommit({bool isFinal = false}) {
    if (!isFinal) {
      const String commit = '{"type":"input_audio_buffer.commit"}';
      _send(AudioSource.input, commit);
      if (_systemConnected) _send(AudioSource.output, commit);
      return <AudioSource>{};
    }
    final Set<AudioSource> finalized = <AudioSource>{};
    for (final AudioSource source in AudioSource.values) {
      if (_utteranceActive[source]! &&
          (source == AudioSource.input || _systemConnected)) {
        finalized.add(source);
        _finalizeSource(source);
      }
    }
    return finalized;
  }

  void _finalizeSource(AudioSource source) {
    const String finalCommit =
        '{"type":"input_audio_buffer.commit","final":true}';
    final int start = _utteranceStartedMs[source]!;
    final int lastVoiced = _lastVoicedMs[source]!;
    _send(
      source,
      finalCommit,
      window: UtteranceWindow(
        startMs: start,
        endMs: lastVoiced > start ? lastVoiced : start,
        hadSpeech: _voicedMs[source]! >= _minSpeechMs,
      ),
    );
    _utteranceActive[source] = false;
    _utteranceStartedMs[source] = 0;
    _lastVoicedMs[source] = 0;
  }

  @override
  Stream<TranscriptEventRemoteModel> get transcriptionStream =>
      _decode(_mic, AudioSource.input);

  @override
  Stream<TranscriptEventRemoteModel> get systemTranscriptionStream =>
      _decode(_sys, AudioSource.output);

  @override
  Set<AudioSource> get activeSources => _utteranceActive.entries
      .where(
        (MapEntry<AudioSource, bool> entry) =>
            (entry.value ||
                _pendingWindows[entry.key]!.isNotEmpty ||
                (_outages[entry.key]?.hasFinalCommit ?? false)) &&
            (entry.key == AudioSource.input || _systemConnected),
      )
      .map((MapEntry<AudioSource, bool> entry) => entry.key)
      .toSet();

  Stream<TranscriptEventRemoteModel> _decode(
    WebSocketClient client,
    AudioSource source,
  ) {
    return client.messageStream
        .where((String message) => message.isNotEmpty)
        .map((String message) {
          final Map<String, dynamic> json =
              jsonDecode(message) as Map<String, dynamic>;
          final TranscriptEventRemoteModel event =
              TranscriptEventRemoteModel.fromJson(json);
          final Queue<UtteranceWindow> windows = _pendingWindows[source]!;
          if (event.type == 'response.audio_transcript.done' &&
              windows.isNotEmpty) {
            _eventWindows[event] = windows.removeFirst();
          }
          return event;
        });
  }

  @override
  UtteranceWindow? windowOf(TranscriptEventRemoteModel event) =>
      _eventWindows[event];

  @override
  Future<void> disconnect() async {
    _clearOutages();
    await Future.wait(<Future<void>>[_mic.disconnect(), _sys.disconnect()]);
    _systemConnected = false;
    _resetUtteranceState();
    _connectionStateSubject.add(domain.ConnectionState.disconnected);
  }

  void _resetUtteranceState() {
    for (final AudioSource source in AudioSource.values) {
      _utteranceActive[source] = false;
      _voicedMs[source] = 0;
      _pendingWindows[source]!.clear();
      _utteranceStartedMs[source] = 0;
      _lastVoicedMs[source] = 0;
    }
  }

  /// Libère les ressources (les deux connexions).
  Future<void> dispose() async {
    _clearOutages();
    await _gapSubject.close();
    await _mic.dispose();
    await _sys.dispose();
    await _connectionStateSubject.close();
  }

  @override
  Stream<domain.ConnectionState> get connectionState =>
      _connectionStateSubject.stream;
}

/// Message en attente pendant une coupure. [timestampMs] n'est renseigné que
/// pour l'audio ; [window] que pour un commit final.
class _Outgoing {
  _Outgoing(this.message, this.timestampMs, this.audioMs, this.window);

  final String message;
  final int? timestampMs;
  final int audioMs;
  final UtteranceWindow? window;
}

/// Coupure d'une source : n'existe que tant que la socket est à rouvrir, donc
/// aucun tampon ne survit à la reconnexion.
class _Outage {
  _Outage(this.maxBufferedMs);

  final int maxBufferedMs;
  final Queue<_Outgoing> queue = Queue<_Outgoing>();
  int bufferedMs = 0;
  int attempts = 0;
  Timer? retry;
  int? lostStartMs;
  int? lostEndMs;

  bool get hasFinalCommit => queue.any((_Outgoing o) => o.window != null);

  /// Garde l'ordre ; au-delà de la borne, jette le plus ancien.
  void add(_Outgoing item) {
    queue.add(item);
    bufferedMs += item.audioMs;
    while (bufferedMs > maxBufferedMs) {
      _lose(queue.removeFirst());
      // Un commit resté en tête ne finaliserait que de l'audio perdu.
      while (queue.isNotEmpty && queue.first.timestampMs == null) {
        _lose(queue.removeFirst());
      }
    }
  }

  void loseAll() {
    while (queue.isNotEmpty) {
      _lose(queue.removeFirst());
    }
  }

  void _lose(_Outgoing item) {
    bufferedMs -= item.audioMs;
    final int? at = item.timestampMs;
    if (at == null) return;
    lostStartMs ??= at;
    lostEndMs = at + item.audioMs;
  }
}
