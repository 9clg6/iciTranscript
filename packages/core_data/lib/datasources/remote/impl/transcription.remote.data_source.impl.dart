import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
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

  // Gate de silence (VAD simple) : chaque source possède son propre tour de
  // parole. Une pause finalise explicitement la session voxmlx correspondante,
  // ce qui borne les caches du modèle et évite la dérive sur les appels longs.
  static const int _voiceThreshold = 350; // amplitude int16 ~ parole
  static const double _voiceStartRms = 300;
  static const double _voiceContinueRms = 180;
  static const int _silenceToFinalizeMs = 700;
  static const int _maxUtteranceMs = 30000;
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
  final Map<AudioSource, int> _finalizationsPending = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };

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
    _systemConnected = systemAudioEnabled;
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
    final int now = chunk.timestampMs;
    final bool voiced = _isVoiced(
      chunk.data,
      alreadyActive: _utteranceActive[source]!,
    );

    if (voiced) {
      if (!_utteranceActive[source]!) {
        _utteranceActive[source] = true;
        _utteranceStartedMs[source] = now;
      }
      _lastVoicedMs[source] = now;
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
    if (chunk.source == AudioSource.output && !_systemConnected) return;
    final WebSocketClient client = chunk.source == AudioSource.input
        ? _mic
        : _sys;
    client.send(
      jsonEncode(<String, String>{
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk.data),
      }),
    );
  }

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
      _mic.send(commit);
      if (_systemConnected) _sys.send(commit);
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
    final WebSocketClient client = source == AudioSource.input ? _mic : _sys;
    client.send(finalCommit);
    _finalizationsPending[source] = _finalizationsPending[source]! + 1;
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
            (entry.value || _finalizationsPending[entry.key]! > 0) &&
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
          if (event.type == 'response.audio_transcript.done' &&
              _finalizationsPending[source]! > 0) {
            _finalizationsPending[source] = _finalizationsPending[source]! - 1;
          }
          return event;
        });
  }

  @override
  Future<void> disconnect() async {
    await Future.wait(<Future<void>>[_mic.disconnect(), _sys.disconnect()]);
    _systemConnected = false;
    _resetUtteranceState();
    _connectionStateSubject.add(domain.ConnectionState.disconnected);
  }

  void _resetUtteranceState() {
    for (final AudioSource source in AudioSource.values) {
      _utteranceActive[source] = false;
      _finalizationsPending[source] = 0;
      _utteranceStartedMs[source] = 0;
      _lastVoicedMs[source] = 0;
    }
  }

  /// Libère les ressources (les deux connexions).
  Future<void> dispose() async {
    await _mic.dispose();
    await _sys.dispose();
    await _connectionStateSubject.close();
  }

  @override
  Stream<domain.ConnectionState> get connectionState =>
      _connectionStateSubject.stream;
}
