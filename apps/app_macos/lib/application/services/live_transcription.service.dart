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
  Timer? _commitTimer;

  // Enregistrement des flux bruts pour la passe post-session (Path B) :
  // micro = MOI, système = interlocuteurs (diarization).
  WavRecorder? _micRecorder;
  WavRecorder? _systemRecorder;

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
  }) async {
    try {
      _log.info('=== DEMARRAGE TRANSCRIPTION ===');

      // 1. Demarrer le serveur ML si pas deja en cours
      final bool serverRunning =
          await _processManagerService.isServerRunning();
      if (!serverRunning) {
        _log.info('Demarrage du serveur ML: $serverCommand');
        await _processManagerService.startServer(
          command: serverCommand,
          args: serverArgs,
          readyPattern: 'Uvicorn running',
        );
        _log.info('Serveur ML demarre OK');
      } else {
        _log.info('Serveur ML deja en cours');
      }

      // 2. Connexion WebSocket
      _log.info('Connexion WebSocket: $webSocketUrl');
      await _transcriptionRemoteDataSource.connect(url: webSocketUrl);
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
      final String? recSessionId = currentSessionStream.valueOrNull?.id;
      if (recSessionId != null) {
        try {
          _micRecorder = WavRecorder();
          _systemRecorder = WavRecorder();
          await _micRecorder!.open('$_recordingsDir/${recSessionId}_mic.wav');
          await _systemRecorder!
              .open('$_recordingsDir/${recSessionId}_system.wav');
        } catch (e) {
          _log.warning('Ouverture enregistreurs WAV échouée: $e');
          _micRecorder = null;
          _systemRecorder = null;
        }
      }

      // 5. Relayer l'audio vers le WebSocket
      int audioChunkCount = 0;
      _audioSubscription = _audioCaptureChannel.audioStream.listen(
        (data.AudioChunk chunk) {
          audioChunkCount++;
          if (audioChunkCount <= 3 || audioChunkCount % 100 == 0) {
            _log.debug(
              'Audio chunk #$audioChunkCount: ${chunk.data.length} bytes, source=${chunk.source}',
            );
          }
          // Tee vers l'enregistreur correspondant (avant le mixage WS).
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
      _log.info('Audio subscription active, en attente de chunks...');

      // 5b. Envoyer des commits periodiques pour declencher la transcription
      _commitTimer?.cancel();
      _commitTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _transcriptionRemoteDataSource.sendCommit();
      });

      // 6. Ecouter les segments de transcription
      _transcriptionSubscription = _transcriptionRemoteDataSource
          .transcriptionStream
          .listen(
            (TranscriptEventRemoteModel event) {
              _handleTranscriptionEvent(event);
            },
            onError: (Object error) {
              _log.error('Erreur transcription stream: $error');
            },
          );

      _log.info('=== TRANSCRIPTION EN DIRECT DEMARREE ===');
    } on Exception catch (e, st) {
      _log.error('Erreur demarrage transcription', e);
      _log.error('Stack: $st');
      await stopTranscription();
      rethrow;
    }
  }

  /// Arrete la session de transcription en direct.
  ///
  /// 1. Arrete la capture audio
  /// 2. Deconnecte le WebSocket
  /// 3. Arrete la session
  Future<void> stopTranscription() async {
    _log.info('Arret de la transcription en direct');

    // Sauvegarder la phrase en cours si non vide (au cas où 'done' n'arrive pas)
    final SessionEntity? currentSession = currentSessionStream.valueOrNull;
    if (currentSession != null && _currentPhrase.isNotEmpty) {
      final String text = _currentPhrase.toString().trim();
      if (text.isNotEmpty) {
        _log.info('Flush phrase en cours avant arret: "$text"');
        final TranscriptSegmentEntity segment = TranscriptSegmentEntity(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: currentSession.id,
          source: AudioSource.input,
          text: text,
          timestampMs: _currentPhraseStartMs,
          createdAt: DateTime.now(),
        );
        await _transcriptionService.saveSegment(segment);
      }
      _currentPhrase = StringBuffer();
    }

    // Annuler le timer de commit
    _commitTimer?.cancel();
    _commitTimer = null;

    // Annuler les subscriptions
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _transcriptionSubscription?.cancel();
    _transcriptionSubscription = null;

    // Arreter la capture audio
    await _audioCaptureChannel.stopCapture();

    // Finaliser les enregistrements WAV (corrige l'en-tête).
    try {
      await _micRecorder?.close();
      await _systemRecorder?.close();
    } catch (e) {
      _log.warning('Fermeture enregistreurs WAV: $e');
    }
    _micRecorder = null;
    _systemRecorder = null;

    // Deconnecte le WebSocket
    await _transcriptionRemoteDataSource.disconnect();

    // Arreter la session
    await _transcriptionService.stopSession();

    _log.info('Transcription en direct arretee');
  }

  /// Libere les ressources du service.
  Future<void> dispose() async {
    _commitTimer?.cancel();
    _commitTimer = null;
    await _audioSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Buffer pour accumuler les deltas en une phrase complete.
  StringBuffer _currentPhrase = StringBuffer();
  int _currentPhraseStartMs = 0;

  void _handleTranscriptionEvent(TranscriptEventRemoteModel event) {
    final SessionEntity? currentSession = currentSessionStream.valueOrNull;
    if (currentSession == null) return;

    if (event.type == 'response.audio_transcript.delta') {
      final String? delta = event.delta;
      if (delta == null || delta.isEmpty) return;

      // Premier mot de la phrase : enregistrer le timestamp
      if (_currentPhrase.isEmpty) {
        _currentPhraseStartMs = DateTime.now()
            .difference(currentSession.createdAt)
            .inMilliseconds;
      }

      // Accumuler les mots
      _currentPhrase.write(delta);

      // Mettre a jour le segment en cours dans l'UI (en temps reel)
      _updateCurrentSegmentInUI(currentSession);
    } else if (event.type == 'response.audio_transcript.done') {
      // Retirer le segment temporaire du stream UI avant de sauvegarder le final
      final List<TranscriptSegmentEntity> currentSegments =
          List<TranscriptSegmentEntity>.from(
            _transcriptionService.segmentsStream.value,
          );
      if (currentSegments.isNotEmpty &&
          currentSegments.last.id.startsWith('current_')) {
        currentSegments.removeLast();
        _transcriptionService.segmentsStream.add(currentSegments);
      }

      // Phrase terminee — sauvegarder le segment final
      final String finalText = event.text ?? _currentPhrase.toString();
      if (finalText.trim().isNotEmpty) {
        final TranscriptSegmentEntity segment = TranscriptSegmentEntity(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: currentSession.id,
          source: AudioSource.input,
          text: finalText.trim(),
          timestampMs: _currentPhraseStartMs,
          createdAt: DateTime.now(),
        );
        _transcriptionService.saveSegment(segment);
      }
      // Reset le buffer pour la prochaine phrase
      _currentPhrase = StringBuffer();
    }
  }

  /// Met a jour le dernier segment en temps reel pendant l'accumulation.
  void _updateCurrentSegmentInUI(SessionEntity session) {
    final String text = _currentPhrase.toString().trim();
    if (text.isEmpty) return;

    // Creer un segment temporaire avec le texte accumule
    final TranscriptSegmentEntity tempSegment = TranscriptSegmentEntity(
      id: 'current_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: session.id,
      source: AudioSource.input,
      text: text,
      timestampMs: _currentPhraseStartMs,
      createdAt: DateTime.now(),
    );

    // Remplacer le dernier segment "en cours" dans la liste
    final List<TranscriptSegmentEntity> segments =
        List<TranscriptSegmentEntity>.from(
          _transcriptionService.segmentsStream.value,
        );

    // Si le dernier segment est un segment temporaire, le remplacer
    if (segments.isNotEmpty && segments.last.id.startsWith('current_')) {
      segments[segments.length - 1] = tempSegment;
    } else {
      segments.add(tempSegment);
    }

    _transcriptionService.segmentsStream.add(segments);
  }
}
