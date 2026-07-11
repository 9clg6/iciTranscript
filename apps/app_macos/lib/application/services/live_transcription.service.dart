import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart' as data;
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:rxdart/rxdart.dart';

/// Service applicatif orchestrant la transcription en direct.
///
/// Coordonne les differentes couches pour fournir un workflow complet :
/// 1. Demarrage/arret du serveur ML via [ProcessManagerService]
/// 2. Capture audio via [AudioCaptureChannel]
/// 3. Envoi audio et reception WebSocket via [TranscriptionRemoteDataSource]
/// 4. Sauvegarde des segments via [TranscriptionService]
/// 5. Gestion de la session via [TranscriptionService]
final class LiveTranscriptionService {
  /// Cree une instance de [LiveTranscriptionService].
  LiveTranscriptionService({
    required ProcessManagerService processManagerService,
    required AudioCaptureChannel audioCaptureChannel,
    required TranscriptionRemoteDataSource transcriptionRemoteDataSource,
    required TranscriptionService transcriptionService,
  }) : _processManagerService = processManagerService,
       _audioCaptureChannel = audioCaptureChannel,
       _transcriptionRemoteDataSource = transcriptionRemoteDataSource,
       _transcriptionService = transcriptionService;

  final ProcessManagerService _processManagerService;
  final AudioCaptureChannel _audioCaptureChannel;
  final TranscriptionRemoteDataSource _transcriptionRemoteDataSource;
  final TranscriptionService _transcriptionService;

  final Log _log = Log.named('LiveTranscriptionService');

  StreamSubscription<data.AudioChunk>? _audioSubscription;
  StreamSubscription<TranscriptEventRemoteModel>? _transcriptionSubscription;
  StreamSubscription<TranscriptEventRemoteModel>?
  _systemTranscriptionSubscription;
  final Set<Future<void>> _pendingFinalizations = <Future<void>>{};
  final Map<AudioSource, Completer<void>> _stopFinalizationWaiters =
      <AudioSource, Completer<void>>{};
  Future<void> _lifecycleTail = Future<void>.value();

  // Enregistrement des flux bruts pour la passe post-session (Path B) :
  // micro = MOI, système = interlocuteurs (diarization).
  WavRecorder? _micRecorder;
  WavRecorder? _systemRecorder;
  bool _recordPostProcessingAudio = false;
  String? _captureInputDeviceId;
  bool _captureOutputEnabled = false;
  bool _capturePaused = false;
  int _audioChunkCount = 0;

  String get _recordingsDir =>
      '${Platform.environment['HOME'] ?? '/tmp'}'
      '/Library/Application Support/IciTranscript/recordings';

  /// Stream reactif de la session en cours.
  BehaviorSubject<SessionEntity?> get currentSessionStream =>
      _transcriptionService.currentSessionStream;

  /// Stream reactif des segments de la session courante.
  BehaviorSubject<List<TranscriptSegmentEntity>> get segmentsStream =>
      _transcriptionService.segmentsStream;

  /// Stream reactif de l'etat du serveur ML.
  Stream<ServerState> get serverStateStream =>
      _processManagerService.stateStream;

  /// Stream reactif indiquant si une transcription est en cours.
  BehaviorSubject<bool> get isRecordingStream =>
      _transcriptionService.isTranscribingStream;

  /// Indique si une transcription est en cours.
  bool get isRecording => _transcriptionService.isTranscribingStream.value;

  /// Vérifie les statuts de permissions (micro + Screen Recording).
  Future<Map<String, String>> checkPermissions() =>
      _audioCaptureChannel.checkPermissions();

  /// Ouvre le panneau de permissions dans les Réglages Système.
  Future<void> openSystemSettings(String pane) =>
      _audioCaptureChannel.openSystemSettings(pane);

  /// Demarre une session de transcription en direct.
  ///
  /// 1. Demarre le serveur ML (si non deja demarre)
  /// 2. Connecte le WebSocket au serveur
  /// 3. Demarre la capture audio
  /// 4. Cree une nouvelle session
  /// 5. Ecoute les segments de transcription
  Future<void> startTranscription({
    String? inputDeviceId,
    bool outputEnabled = false,
    String serverCommand = 'voxmlx-serve',
    List<String> serverArgs = const <String>[],
    String webSocketUrl = 'ws://localhost:8000/v1/realtime',
    bool enablePostProcessing = false,
  }) => _serializeLifecycle(
    () => _startTranscription(
      inputDeviceId: inputDeviceId,
      outputEnabled: outputEnabled,
      serverCommand: serverCommand,
      serverArgs: serverArgs,
      webSocketUrl: webSocketUrl,
      enablePostProcessing: enablePostProcessing,
    ),
  );

  Future<void> _startTranscription({
    required String? inputDeviceId,
    required bool outputEnabled,
    required String serverCommand,
    required List<String> serverArgs,
    required String webSocketUrl,
    required bool enablePostProcessing,
  }) async {
    if (isRecording) {
      _log.warning('Une transcription est déjà en cours');
      return;
    }
    try {
      _log.info('=== DEMARRAGE TRANSCRIPTION ===');
      _captureInputDeviceId = inputDeviceId;
      _captureOutputEnabled = outputEnabled;
      _capturePaused = false;
      _audioChunkCount = 0;

      // 1. Demarrer le serveur ML si pas deja en cours
      final bool serverRunning = await _processManagerService.isServerRunning();
      if (!serverRunning) {
        _log.info('Demarrage du serveur ML: $serverCommand');
        await _processManagerService.startServer(
          command: serverCommand,
          args: serverArgs,
          readyPattern: 'VOXMLX_READY',
        );
        _log.info('Serveur ML demarre OK');
      } else {
        _log.info('Serveur ML deja en cours');
      }

      // 2. Connexion WebSocket
      _log.info('Connexion WebSocket: $webSocketUrl');
      await _transcriptionRemoteDataSource.connect(
        url: webSocketUrl,
        systemAudioEnabled: outputEnabled,
      );
      _log.info('WebSocket connecte OK');

      // 3. Demarrer la capture audio
      _log.info('Demarrage capture audio...');
      try {
        await _audioCaptureChannel.startCapture(
          inputDeviceId: inputDeviceId,
          outputEnabled: outputEnabled,
        );
        _log.info('Capture audio demarree OK');
      } on PlatformException catch (e) {
        // Seul le micro est bloquant : sans micro, rien à transcrire
        if (e.code == 'MIC_PERMISSION_DENIED') {
          _log.error('Erreur permission micro: ${e.code}');
          rethrow;
        }
        // SCREEN_RECORDING_DENIED et autres erreurs : non bloquant, continuer en mode micro seul
        _log.warning('Erreur capture audio bureau (non bloquant): $e');
      } catch (audioError) {
        _log.warning('Erreur capture audio (non bloquant): $audioError');
      }

      // 4. Creer une nouvelle session
      _log.info('Creation session...');
      await _transcriptionService.startSession();
      _log.info('Session creee OK');

      // 4b. Ouvrir les enregistreurs WAV par session (micro + système) pour la
      // passe post-session (transcription propre MOI + diarization meeting).
      _recordPostProcessingAudio = enablePostProcessing;
      final String? recSessionId = currentSessionStream.valueOrNull?.id;
      if (_recordPostProcessingAudio && recSessionId != null) {
        try {
          _micRecorder = WavRecorder();
          _systemRecorder = WavRecorder();
          await _micRecorder!.open('$_recordingsDir/${recSessionId}_mic.wav');
          await _systemRecorder!.open(
            '$_recordingsDir/${recSessionId}_system.wav',
          );
        } catch (e) {
          _log.warning('Ouverture enregistreurs WAV échouée: $e');
          _micRecorder = null;
          _systemRecorder = null;
        }
      }

      // 5. Écouter les deux flux avant de relayer l'audio. Ainsi, aucun delta
      // ni `done` ne peut être perdu si le serveur répond immédiatement.
      _transcriptionSubscription = _transcriptionRemoteDataSource
          .transcriptionStream
          .listen(
            (TranscriptEventRemoteModel event) =>
                _handleTranscriptionEvent(event, AudioSource.input),
            onError: (Object error) =>
                _log.error('Erreur transcription micro: $error'),
          );
      _systemTranscriptionSubscription = _transcriptionRemoteDataSource
          .systemTranscriptionStream
          .listen(
            (TranscriptEventRemoteModel event) =>
                _handleTranscriptionEvent(event, AudioSource.output),
            onError: (Object error) =>
                _log.error('Erreur transcription système: $error'),
          );

      // 6. Relayer l'audio vers le WebSocket.
      _subscribeToAudio();
      _log.info('Audio subscription active, en attente de chunks...');

      _log.info('=== TRANSCRIPTION EN DIRECT DEMARREE ===');
    } catch (e, st) {
      _log.error('Erreur demarrage transcription', e);
      _log.error('Stack: $st');
      await _stopTranscription();
      rethrow;
    }
  }

  /// Arrete la session de transcription en direct.
  ///
  /// 1. Arrete la capture audio
  /// 2. Deconnecte le WebSocket
  /// 3. Arrete la session
  Future<void> stopTranscription() => _serializeLifecycle(_stopTranscription);

  /// Met réellement la capture en pause et finalise les tours en cours.
  Future<void> pauseTranscription() => _serializeLifecycle(_pauseTranscription);

  /// Relance la capture avec les mêmes périphériques, sans créer de session.
  Future<void> resumeTranscription() =>
      _serializeLifecycle(_resumeTranscription);

  Future<void> _pauseTranscription() async {
    if (!isRecording || _capturePaused) return;
    _capturePaused = true;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _audioCaptureChannel.stopCapture();
    await _flushRemoteTranscripts();
    _log.info('Capture audio mise en pause');
  }

  Future<void> _resumeTranscription() async {
    if (!isRecording || !_capturePaused) return;
    _subscribeToAudio();
    try {
      await _audioCaptureChannel.startCapture(
        inputDeviceId: _captureInputDeviceId,
        outputEnabled: _captureOutputEnabled,
      );
      _capturePaused = false;
      _log.info('Capture audio reprise');
    } catch (_) {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      rethrow;
    }
  }

  Future<void> _stopTranscription() async {
    _log.info('Arret de la transcription en direct');

    // Couper d'abord la capture afin que plus aucun chunk ne soit ajouté pendant
    // la finalisation des deux sessions voxmlx.
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await _audioCaptureChannel.stopCapture();
    } catch (e) {
      _log.warning('Arrêt capture audio: $e');
    }

    // Demander un vrai flush serveur et laisser les listeners recevoir les
    // derniers deltas + `done`. Un timeout conserve un fallback local fiable.
    await _flushRemoteTranscripts();

    // Plus aucun événement distant après ce point : cela évite qu'un `done`
    // tardif duplique le fallback local.
    await _transcriptionSubscription?.cancel();
    _transcriptionSubscription = null;
    await _systemTranscriptionSubscription?.cancel();
    _systemTranscriptionSubscription = null;
    _stopFinalizationWaiters.clear();

    // Sauvegarder les phrases restantes si le serveur n'a pas répondu à temps.
    final SessionEntity? currentSession = currentSessionStream.valueOrNull;
    if (currentSession != null) {
      for (final AudioSource source in AudioSource.values) {
        final String text = _phrase[source]!.toString().trim();
        if (text.isEmpty) continue;
        await _finalizeSegment(currentSession, source, text);
      }
    }

    if (_pendingFinalizations.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.from(_pendingFinalizations));
    }

    // Finaliser les enregistrements WAV (corrige l'en-tête).
    try {
      await _micRecorder?.close();
      await _systemRecorder?.close();
    } catch (e) {
      _log.warning('Fermeture enregistreurs WAV: $e');
    }
    _micRecorder = null;
    _systemRecorder = null;
    _recordPostProcessingAudio = false;
    _capturePaused = false;
    _captureInputDeviceId = null;
    _captureOutputEnabled = false;

    // Deconnecte le WebSocket
    await _transcriptionRemoteDataSource.disconnect();

    // Arreter la session
    await _transcriptionService.stopSession();

    _log.info('Transcription en direct arretee');
  }

  /// Libere les ressources du service.
  Future<void> dispose() async {
    await _audioSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
    await _systemTranscriptionSubscription?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  Future<T> _serializeLifecycle<T>(Future<T> Function() action) {
    final Completer<T> result = Completer<T>();
    final Future<void> previous = _lifecycleTail;
    _lifecycleTail = () async {
      try {
        await previous;
      } catch (_) {
        // Une opération échouée ne doit pas bloquer les suivantes.
      }
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }();
    return result.future;
  }

  void _subscribeToAudio() {
    _audioSubscription = _audioCaptureChannel.audioStream.listen(
      (data.AudioChunk chunk) {
        _audioChunkCount++;
        if (_audioChunkCount <= 3 || _audioChunkCount % 100 == 0) {
          _log.debug(
            'Audio chunk #$_audioChunkCount: ${chunk.data.length} bytes, '
            'source=${chunk.source}',
          );
        }
        if (chunk.source == AudioSource.input) {
          _micRecorder?.append(chunk.data);
        } else {
          _systemRecorder?.append(chunk.data);
        }
        _transcriptionRemoteDataSource.sendAudio(chunk);
      },
      onError: (Object error) {
        _log.error('Erreur capture audio stream: $error');
      },
    );
  }

  Future<void> _flushRemoteTranscripts() async {
    final Set<AudioSource> sourcesToFinalize =
        _transcriptionRemoteDataSource.activeSources;
    _stopFinalizationWaiters.clear();
    for (final AudioSource source in sourcesToFinalize) {
      _stopFinalizationWaiters[source] = Completer<void>();
    }
    _transcriptionRemoteDataSource.sendCommit(isFinal: true);
    if (_stopFinalizationWaiters.isEmpty) return;
    try {
      await Future.wait<void>(
        _stopFinalizationWaiters.values.map(
          (Completer<void> completer) => completer.future,
        ),
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _log.warning('Timeout du flush final voxmlx, fallback sur les deltas');
    } finally {
      _stopFinalizationWaiters.clear();
    }
  }

  /// Buffers d'accumulation des deltas, par source (micro / système).
  final Map<AudioSource, StringBuffer> _phrase = <AudioSource, StringBuffer>{
    AudioSource.input: StringBuffer(),
    AudioSource.output: StringBuffer(),
  };
  final Map<AudioSource, int> _phraseStart = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };

  String _tempId(AudioSource source) => 'current_${source.name}';

  void _handleTranscriptionEvent(
    TranscriptEventRemoteModel event,
    AudioSource source,
  ) {
    final SessionEntity? currentSession = currentSessionStream.valueOrNull;
    if (currentSession == null) return;

    if (event.type == 'response.audio_transcript.delta') {
      final String? delta = event.delta;
      if (delta == null || delta.isEmpty) return;

      if (_phrase[source]!.isEmpty) {
        _phraseStart[source] = DateTime.now()
            .difference(currentSession.createdAt)
            .inMilliseconds;
      }
      _phrase[source]!.write(delta);

      _updateCurrentSegmentInUI(currentSession, source);
    } else if (event.type == 'response.audio_transcript.done') {
      _trackFinalization(
        currentSession,
        source,
        event.text ?? _phrase[source]!.toString(),
      );
    }
  }

  /// Finalise la phrase courante d'une source : remplace le segment temporaire
  /// par un segment définitif (sauvé en base) et réinitialise le buffer.
  Future<void> _finalizeSegment(
    SessionEntity session,
    AudioSource source,
    String rawText,
  ) async {
    final List<TranscriptSegmentEntity> segs =
        List<TranscriptSegmentEntity>.from(
          _transcriptionService.segmentsStream.value,
        )..removeWhere((TranscriptSegmentEntity s) => s.id == _tempId(source));

    final int phraseStart = _phraseStart[source]!;
    _phrase[source] = StringBuffer();
    final String text = TranscriptTextNormalizer.normalize(rawText);
    _transcriptionService.segmentsStream.add(segs);
    if (text.isNotEmpty) {
      final TranscriptSegmentEntity segment = TranscriptSegmentEntity(
        id: '${source.name}_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: session.id,
        source: source,
        text: text,
        timestampMs: phraseStart,
        createdAt: DateTime.now(),
      );
      await _transcriptionService.saveSegment(segment);
    }
    _sortAndDedupeSegments();
  }

  /// Met a jour le segment temporaire (par source) en temps reel.
  void _updateCurrentSegmentInUI(SessionEntity session, AudioSource source) {
    final String text = TranscriptTextNormalizer.normalize(
      _phrase[source]!.toString(),
    );
    if (text.isEmpty) return;

    final TranscriptSegmentEntity tempSegment = TranscriptSegmentEntity(
      id: _tempId(source),
      sessionId: session.id,
      source: source,
      text: text,
      timestampMs: _phraseStart[source]!,
      createdAt: DateTime.now(),
    );

    final List<TranscriptSegmentEntity> segments =
        List<TranscriptSegmentEntity>.from(
          _transcriptionService.segmentsStream.value,
        );
    final int idx = segments.indexWhere(
      (TranscriptSegmentEntity s) => s.id == _tempId(source),
    );
    if (idx >= 0) {
      segments[idx] = tempSegment;
    } else {
      segments.add(tempSegment);
    }
    segments.sort(
      (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
          a.timestampMs.compareTo(b.timestampMs),
    );
    _transcriptionService.segmentsStream.add(segments);
  }

  void _trackFinalization(
    SessionEntity session,
    AudioSource source,
    String rawText,
  ) {
    late final Future<void> task;
    task = _finalizeSegment(session, source, rawText).whenComplete(() {
      _pendingFinalizations.remove(task);
      // Plusieurs commits peuvent déjà être en vol si le modèle a pris du
      // retard. Ne couper les listeners qu'après le dernier `done` de la
      // source, sinon les fins de phrases suivantes seraient perdues.
      if (!_transcriptionRemoteDataSource.activeSources.contains(source)) {
        final Completer<void>? waiter = _stopFinalizationWaiters.remove(source);
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      }
    });
    _pendingFinalizations.add(task);
    unawaited(task);
  }

  void _sortAndDedupeSegments() {
    final Map<String, TranscriptSegmentEntity> byId =
        <String, TranscriptSegmentEntity>{};
    for (final TranscriptSegmentEntity segment
        in _transcriptionService.segmentsStream.value) {
      byId[segment.id] = segment;
    }
    final List<TranscriptSegmentEntity> sorted = byId.values.toList()
      ..sort((TranscriptSegmentEntity a, TranscriptSegmentEntity b) {
        final int byTimestamp = a.timestampMs.compareTo(b.timestampMs);
        return byTimestamp != 0
            ? byTimestamp
            : a.createdAt.compareTo(b.createdAt);
      });
    _transcriptionService.segmentsStream.add(sorted);
  }
}
