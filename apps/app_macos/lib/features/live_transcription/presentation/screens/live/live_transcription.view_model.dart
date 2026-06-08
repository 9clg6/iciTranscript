import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/diarization.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/core/providers/services/translation.service.provider.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_transcription.view_model.g.dart';

/// ViewModel de l'ecran de transcription en direct.
@Riverpod(keepAlive: true)
class LiveTranscriptionViewModel extends _$LiveTranscriptionViewModel {
  final Log _log = Log.named('LiveTranscriptionViewModel');
  Timer? _durationTimer;
  LiveTranscriptionService? _liveService;
  bool _subscribed = false;

  @override
  LiveTranscriptionState build() {
    _liveService = ref.watch(liveTranscriptionServiceProvider);

    // Ecouter les streams et vérifier les permissions UNE seule fois.
    // Ne pas appeler recheckPermissions() à chaque rebuild : en macOS 15,
    // CGPreflightScreenCaptureAccess() peut déclencher le dialog de permission.
    if (!_subscribed) {
      _subscribed = true;
      _listenToStreams();
      Future<void>.microtask(() => recheckPermissions());
    }

    ref.onDispose(() {
      _durationTimer?.cancel();
    });

    return LiveTranscriptionState.initial();
  }

  void _listenToStreams() {
    // Ecoute l'etat du serveur
    ref.watch(processManagerServiceProvider).stateStream.listen((
      ServerState serverState,
    ) {
      state = state.copyWith(serverState: serverState);
    });

    // Ecoute les segments de la transcription
    _liveService?.segmentsStream.listen((
      List<TranscriptSegmentEntity> segments,
    ) {
      _log.debug('Segments mis a jour: ${segments.length}');
      state = state.copyWith(segments: segments);
      _translateNewSegments(segments);
    });

    // Ecoute l'etat d'enregistrement
    _liveService?.isRecordingStream.listen((bool isRecording) {
      _log.debug('isRecording: $isRecording');
      state = state.copyWith(isRecording: isRecording);
      if (!isRecording) {
        _durationTimer?.cancel();
        _durationTimer = null;
      }
    });
  }

  /// Demarre une nouvelle session de transcription.
  Future<void> startSession() async {
    _log.info('startSession() appele');

    state = state.copyWith(
      isRecording: true,
      isPaused: false,
      segments: <TranscriptSegmentEntity>[],
      duration: Duration.zero,
      feedback: null,
    );

    _startDurationTimer();

    try {
      final String? micId =
          ref.read(settingsViewModelProvider).selectedMicId;
      final bool systemAudio =
          ref.read(settingsViewModelProvider).systemAudioEnabled;
      await _liveService?.startTranscription(
        inputDeviceId: micId,
        serverCommand: 'uvx',
        serverArgs: const <String>[
          '--from',
          'git+https://github.com/T0mSIlver/voxmlx.git[server]',
          'voxmlx-serve',
          '--model',
          'T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit',
        ],
        outputEnabled: systemAudio,
      );
      _log.info('startTranscription OK');
    } catch (e) {
      _log.error('ERREUR startTranscription: $e');
      if (e is PlatformException && e.code == 'MIC_PERMISSION_DENIED') {
        state = state.copyWith(isRecording: false, micPermission: 'denied');
      } else {
        state = state.copyWith(
          isRecording: false,
          serverState: ServerState.error,
        );
      }
      _durationTimer?.cancel();
      await _liveService?.stopTranscription();
    }
  }

  /// Arrete la session, sauvegarde la transcription et génère un résumé si activé.
  Future<void> stopSession() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    // Capturer l'ID de session avant d'arrêter
    final String? sessionId =
        _liveService?.currentSessionStream.value?.id;

    await _liveService?.stopTranscription();

    final List<TranscriptSegmentEntity> segments = state.segments;
    // Vider les segments immédiatement — chaque session commence vierge
    state = state.copyWith(
      isRecording: false,
      isPaused: false,
      segments: <TranscriptSegmentEntity>[],
      duration: Duration.zero,
    );

    // Sauvegarder la transcription en local
    await _saveTranscriptToFile(segments);

    // Rafraichir la liste des sessions dans la sidebar
    await ref.read(sessionHistoryServiceProvider).loadSessions();

    // Libérer le GPU/RAM du serveur de transcription (Voxtral MLX) avant les
    // traitements lourds. Sinon voxmlx-serve + voxmlx (diarization) + ollama
    // tournent en même temps sur la mémoire unifiée → crash machine.
    try {
      await ref.read(processManagerServiceProvider).stopServer();
    } catch (e) {
      _log.warning('Arrêt serveur transcription avant post-traitement: $e');
    }

    // Passe post-session : transcription propre du micro (MOI) + diarization
    // du flux système (interlocuteurs). Auto à la fin de session.
    final String? micText = await _diarizeAndStore(sessionId);

    // Analyser l'anglais si l'option est activée — sur le micro UNIQUEMENT.
    if (state.isCoachEnabled) {
      final String transcript = micText ??
          segments
              .where(
                (TranscriptSegmentEntity s) => s.source == AudioSource.input,
              )
              .map((TranscriptSegmentEntity s) => s.text)
              .join('\n');
      await _analyzeEnglish(transcript, sessionId: sessionId);
    }
  }

  /// Lance la passe post-session (diarization + transcription propre) et
  /// fusionne le résultat dans l'enveloppe stockée. Renvoie le texte du micro.
  Future<String?> _diarizeAndStore(String? sessionId) async {
    if (sessionId == null) return null;
    try {
      final DiarizationResult? result =
          await ref.read(diarizationServiceProvider).processSession(sessionId);
      if (result == null) return null;

      final SessionAnalysis existing = SessionAnalysis.fromStored(
        await ref.read(summaryServiceProvider).getSummaryForSession(sessionId),
      );
      await ref.read(summaryServiceProvider).saveSummary(
            sessionId: sessionId,
            content: existing
                .copyWith(
                  micText: result.micText,
                  speakers: result.speakers,
                )
                .toStored(),
          );
      _log.info(
        'Diarization stockée: ${result.speakers.length} tours, '
        'micText=${result.micText != null}',
      );
      return result.micText;
    } catch (e) {
      _log.error('Diarization post-session échouée: $e');
      return null;
    }
  }

  /// Active ou désactive le coach d'anglais.
  void toggleCoach() {
    state = state.copyWith(isCoachEnabled: !state.isCoachEnabled);
  }

  /// Active/désactive la traduction temps réel.
  void toggleTranslation() {
    final bool enabled = !state.isTranslationEnabled;
    state = state.copyWith(isTranslationEnabled: enabled);
    if (enabled) _translateNewSegments(state.segments);
  }

  /// Change les langues de traduction et retraduit.
  void setTranslationLangs({String? from, String? to}) {
    state = state.copyWith(
      translationFrom: from ?? state.translationFrom,
      translationTo: to ?? state.translationTo,
      translations: <String, String>{},
    );
    if (state.isTranslationEnabled) _translateNewSegments(state.segments);
  }

  /// Traduit les nouveaux segments finalisés (par phrase, en tâche de fond).
  void _translateNewSegments(List<TranscriptSegmentEntity> segments) {
    if (!state.isTranslationEnabled) return;
    final String from = state.translationFrom;
    final String to = state.translationTo;
    for (final TranscriptSegmentEntity s in segments) {
      if (s.id.startsWith('current_')) continue; // phrase en cours
      if (state.translations.containsKey(s.id)) continue;
      // Réserver l'entrée pour éviter les requêtes dupliquées.
      state = state.copyWith(
        translations: <String, String>{...state.translations, s.id: ''},
      );
      ref
          .read(translationServiceProvider)
          .translate(text: s.text, from: from, to: to)
          .then((String t) {
        if (t.isEmpty) return;
        state = state.copyWith(
          translations: <String, String>{...state.translations, s.id: t},
        );
      });
    }
  }

  /// Met en pause.
  void pauseSession() {
    _durationTimer?.cancel();
    state = state.copyWith(isPaused: true);
  }

  /// Reprend.
  void resumeSession() {
    state = state.copyWith(isPaused: false);
    _startDurationTimer();
  }

  /// Vérifie les permissions et met à jour le state.
  Future<void> recheckPermissions() async {
    try {
      final Map<String, String> perms =
          await _liveService?.checkPermissions() ?? <String, String>{};
      state = state.copyWith(
        micPermission: perms['mic'] ?? 'unknown',
        screenRecordingPermission: perms['screenRecording'] ?? 'unknown',
      );
    } catch (_) {
      // Silencieux — ne pas crasher si la vérification échoue
    }
  }

  /// Ouvre les Réglages Système pour la permission microphone.
  Future<void> openMicSettings() async {
    await _liveService?.openSystemSettings('microphone');
  }

  /// Ouvre les Réglages Système pour la permission Screen Recording.
  Future<void> openScreenRecordingSettings() async {
    await _liveService?.openSystemSettings('screenRecording');
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isPaused) {
        state = state.copyWith(
          duration: state.duration + const Duration(seconds: 1),
        );
      }
    });
  }

  /// Sauvegarde la transcription dans un fichier texte local.
  Future<void> _saveTranscriptToFile(
    List<TranscriptSegmentEntity> segments,
  ) async {
    if (segments.isEmpty) return;
    try {
      final String home = Platform.environment['HOME'] ?? '';
      final Directory dir = Directory(
        '$home/Library/Application Support/IciTranscript/transcripts',
      );
      await dir.create(recursive: true);

      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File('${dir.path}/transcript_$timestamp.txt');

      final StringBuffer buffer = StringBuffer();
      for (final TranscriptSegmentEntity segment in segments) {
        final Duration ts = Duration(milliseconds: segment.timestampMs);
        final String time =
            '${ts.inMinutes.toString().padLeft(2, '0')}:${(ts.inSeconds % 60).toString().padLeft(2, '0')}';
        buffer.writeln('[$time] ${segment.text}');
      }

      await file.writeAsString(buffer.toString());
      _log.info('Transcription sauvegardee: ${file.path}');
    } catch (e) {
      _log.error('Erreur sauvegarde transcription: $e');
    }
  }

  /// Analyse l'anglais parlé via Ollama (Mistral local) et sauvegarde le retour.
  ///
  /// [transcript] = parole du micro (MOI) uniquement.
  Future<void> _analyzeEnglish(
    String transcript, {
    String? sessionId,
  }) async {
    if (transcript.trim().isEmpty) return;
    state = state.copyWith(isFeedbackLoading: true);

    // S'assurer qu'Ollama est prêt (téléchargement binaire + modèle si besoin)
    try {
      await ref.read(ollamaServiceProvider).ensureReady(
        onProgress: (OllamaSetupStage stage, double progress) {
          state = state.copyWith(
            ollamaSetupStage: stage,
            ollamaSetupProgress: progress,
          );
        },
      );
      state = state.copyWith(
        ollamaSetupStage: OllamaSetupStage.idle,
        ollamaSetupProgress: 0,
      );
    } catch (e) {
      _log.error('Ollama setup échoué: $e');
      state = state.copyWith(
        isFeedbackLoading: false,
        ollamaSetupStage: OllamaSetupStage.error,
        ollamaSetupError: e.toString(),
        feedback: EnglishFeedbackEntity(overall: 'Erreur Ollama : $e'),
      );
      return;
    }

    try {
      final EnglishFeedbackEntity feedback =
          await ref.read(ollamaServiceProvider).analyzeEnglish(transcript);

      state = state.copyWith(isFeedbackLoading: false, feedback: feedback);
      _log.info(
        'Analyse anglais terminée (${feedback.corrections.length} corrections)',
      );

      // Sauvegarder le retour dans l'enveloppe partagée (résumé + coach).
      if (sessionId != null && feedback.corrections.isNotEmpty) {
        final SessionAnalysis existing = SessionAnalysis.fromStored(
          await ref.read(summaryServiceProvider).getSummaryForSession(
            sessionId,
          ),
        );
        await ref.read(summaryServiceProvider).saveSummary(
          sessionId: sessionId,
          content: existing.copyWith(feedback: feedback).toStored(),
        );
        _log.info('Retour coach sauvegardé pour session $sessionId');
      }
    } catch (e) {
      _log.error('Erreur analyse anglais Ollama: $e');
      state = state.copyWith(
        isFeedbackLoading: false,
        feedback: EnglishFeedbackEntity(overall: 'Erreur Ollama : $e'),
      );
    }
  }
}
