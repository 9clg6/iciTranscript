import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/application/services/session_audio.dart';
import 'package:ici_transcript/core/providers/services/gap_backfill_retry.provider.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/calendar/calendar_rules.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/platform/voxmlx_server.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/diarization.service.provider.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/ready_llm.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/core/providers/services/translation.service.provider.dart';
import 'package:ici_transcript/core/providers/services/transcription_server_arbiter.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_transcription.view_model.g.dart';

/// Attente maximale de l'agenda au démarrage d'une note ; au-delà, la note
/// démarre sans lien.
const Duration kCalendarLinkTimeout = Duration(seconds: 1);

/// ViewModel de l'ecran de transcription en direct.
@Riverpod(keepAlive: true)
class LiveTranscriptionViewModel extends _$LiveTranscriptionViewModel {
  final Log _log = Log.named('LiveTranscriptionViewModel');
  Timer? _durationTimer;
  final Map<String, Timer> _translateDebounces = <String, Timer>{};
  final Map<String, int> _translationRetries = <String, int>{};
  int _translationGeneration = 0;
  LiveTranscriptionService? _liveService;
  bool _subscribed = false;
  Future<void>? _postProcessTask;
  // Un interrupteur touché avant la fin de la lecture de prefs.json garde la
  // valeur choisie.
  bool _coachTouched = false;
  bool _speakersTouched = false;
  bool _liveCoachTouched = false;
  bool _startRequested = false;

  CalendarEvent? _nextEvent;

  static const String _coachKey = 'coach_enabled';
  static const String _speakersKey = 'live_speakers_enabled';
  static const String _liveCoachKey = 'live_coach_enabled';

  @override
  LiveTranscriptionState build() {
    _liveService = ref.watch(liveTranscriptionServiceProvider);

    // Ecouter les streams et vérifier les permissions UNE seule fois.
    // Ne pas appeler recheckPermissions() à chaque rebuild : en macOS 15,
    // CGPreflightScreenCaptureAccess() peut déclencher le dialog de permission.
    if (!_subscribed) {
      _subscribed = true;
      _listenToStreams();
      unawaited(_loadSwitches());
      Future<void>.microtask(() => recheckPermissions());
    }

    ref.onDispose(() {
      _durationTimer?.cancel();
      _translationGeneration++;
      for (final Timer timer in _translateDebounces.values) {
        timer.cancel();
      }
      _translateDebounces.clear();
      _translationRetries.clear();
    });

    return LiveTranscriptionState.initial();
  }

  void _listenToStreams() {
    // Ecoute l'etat du serveur
    ref.watch(processManagerServiceProvider).stateStream.listen((
      ServerState serverState,
    ) {
      state = state.copyWith(
        serverState: serverState,
        serverStartupLine: serverState == ServerState.starting
            ? state.serverStartupLine
            : null,
        // Effacé seulement au prochain démarrage : les états `stopped` puis
        // `error` d'un échec peuvent arriver après le catch qui le pose.
        serverPortInUse: serverState == ServerState.starting
            ? null
            : state.serverPortInUse,
      );
    });

    // Premier lancement : installation + téléchargement du modèle peuvent
    // prendre plusieurs minutes. Afficher où en est le serveur.
    ref.watch(processManagerServiceProvider).logsStream.listen((String line) {
      if (state.serverState != ServerState.starting) return;
      final String? text = _startupLine(line);
      if (text != null) state = state.copyWith(serverStartupLine: text);
    });

    // Son du Mac : capté ou non (autorisation, erreur ScreenCaptureKit).
    _liveService?.captureStatusStream.listen((Map<String, String> status) {
      switch (status['type']) {
        case 'outputActive':
          state = state.copyWith(
            screenRecordingPermission: 'authorized',
            systemAudioError: null,
          );
        case 'outputUnavailable':
          _log.warning('Son du Mac non capté: $status');
          final bool denied = status['reason'] == 'SCREEN_RECORDING_DENIED';
          state = state.copyWith(
            screenRecordingPermission: denied
                ? 'denied'
                : state.screenRecordingPermission,
            systemAudioError: denied ? null : status['message'] ?? 'erreur',
          );
      }
    });

    // Ecoute les segments de la transcription
    _liveService?.segmentsStream.listen((
      List<TranscriptSegmentEntity> segments,
    ) {
      _log.debug('Segments mis a jour: ${segments.length}');
      state = state.copyWith(segments: segments);
      _translateNewSegments(segments);
    });

    // Phrases finales : contexte et porte des questions en direct.
    _liveService?.finalizedSegmentsStream.listen((
      TranscriptSegmentEntity segment,
    ) {
      _answers.onSegmentFinalized(
        segment,
        speaker: _liveService?.speakerLabels[segment.id],
      );
      // Ignoré hors d'une note où le coach en direct est activé.
      _coach.onSegmentFinalized(segment);
    });

    // Après Arrêter : rattrapage restant, pour l'état « Finalisation… ».
    _liveService?.finalisingRemainingStream.listen((Duration remaining) {
      state = state.copyWith(
        finalisingRemaining: remaining > Duration.zero ? remaining : null,
      );
    });

    // Place disque, copie audio (WAV) et lignes non rangées.
    _liveService?.storageStream.listen((RecordingStorage storage) {
      state = state.copyWith(storage: storage);
    });

    // Interlocuteurs identifiés en direct sur l'audio système.
    _liveService?.speakerLabelsStream.listen((Map<String, int> labels) {
      state = state.copyWith(speakerLabels: labels);
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

  /// Ligne lisible du journal du serveur, sans bruit ni codes ANSI.
  static String? _startupLine(String line) {
    String text = line
        .replaceFirst(RegExp(r'^\[(stdout|stderr)\]\s*'), '')
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '')
        .trim();
    // Barres de progression : garder la dernière mise à jour.
    if (text.contains('\r')) text = text.split('\r').last.trim();
    if (text.isEmpty) return null;
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  LiveAnswersService get _answers => ref.read(liveAnswersServiceProvider);

  LiveCoachService get _coach => ref.read(liveCoachServiceProvider);

  /// Demarre une nouvelle session de transcription.
  Future<void> startSession() async {
    // Dès la demande : la passe du coach d'après l'appel s'arrête entre
    // deux lots (attendue ci-dessous, elle retarderait le démarrage).
    _startRequested = true;
    try {
      await _startSession();
    } finally {
      _startRequested = false;
    }
  }

  /// Un enregistrement est demandé ou en cours (ou une dictée) : même
  /// règle que le rattrapage des pertes, plus la demande en attente et
  /// l'état de l'écran du direct.
  bool _recordingWanted() =>
      _startRequested ||
      state.isRecording ||
      ref.read(transcriptionServerArbiterProvider).backfillMustYield;

  Future<void> _startSession() async {
    _log.info('startSession() appele');

    // Les modèles Voxtral, Ollama et Parakeet partagent la mémoire unifiée.
    // Si le coach optionnel de la session précédente tourne encore, attendre
    // sa libération avant de relancer la transcription évite une course Metal
    // et l'arrêt du nouveau serveur par l'ancienne tâche.
    final Future<void>? previousPostProcess = _postProcessTask;
    if (previousPostProcess != null) {
      _log.info('Attente du post-traitement précédent');
      await previousPostProcess;
    }

    state = state.copyWith(
      isRecording: true,
      isPaused: false,
      segments: <TranscriptSegmentEntity>[],
      duration: Duration.zero,
      feedback: null,
      translations: <String, String>{},
      speakerLabels: <String, int>{},
      systemAudioError: null,
    );
    _translationGeneration++;
    _cancelTranslationDebounces();
    if (state.isTranslationEnabled) unawaited(_prepareTranslationPair());

    _startDurationTimer();

    try {
      final SessionCalendarLink? calendarLink = await _calendarLink();
      final String? micId = ref.read(settingsViewModelProvider).selectedMicId;
      final bool systemAudio = ref
          .read(settingsViewModelProvider)
          .systemAudioEnabled;
      final TranscriptionEngine engine = await _engine();
      await _liveService?.startTranscription(
        engine: engine,
        inputDeviceId: micId,
        serverCommand: voxmlxCommand,
        serverArgs: voxmlxArgs(),
        outputEnabled: systemAudio,
        enablePostProcessing: state.isCoachEnabled,
        liveDiarization: state.isLiveSpeakersEnabled,
        calendarLink: calendarLink,
      );
      _log.info('startTranscription OK');
      final SessionEntity? session = _liveService?.currentSessionStream.value;
      state = state.copyWith(sessionTitle: session?.title);
      if (session != null) {
        _answers.start(session.id);
        if (state.isLiveCoachEnabled) _coach.start(session.id);
      }
    } catch (e) {
      _log.error('ERREUR startTranscription: $e');
      if (e is PlatformException && e.code == 'MIC_PERMISSION_DENIED') {
        state = state.copyWith(isRecording: false, micPermission: 'denied');
      } else {
        state = state.copyWith(
          isRecording: false,
          serverState: ServerState.error,
          serverPortInUse: e is PortInUseException ? e.port : null,
        );
      }
      _durationTimer?.cancel();
      await _answers.stop();
      await _coach.stop();
      await _liveService?.stopTranscription();
    }
  }

  /// Événement de l'agenda auquel lier la note qui démarre (règle
  /// [eventToLink]) ; null si l'agenda n'est pas connecté, pas autorisé ou
  /// illisible. Ni titre ni participants ne vont au journal.
  Future<SessionCalendarLink?> _calendarLink() async {
    final CalendarEvent? chosen = _nextEvent;
    _nextEvent = null;
    if (chosen != null) return _linkTo(chosen);
    try {
      // Un agenda muet ne retarde jamais l'enregistrement.
      final CalendarFeed feed = await ref
          .read(calendarFeedControllerProvider.future)
          .timeout(kCalendarLinkTimeout);
      if (feed is! CalendarEvents) return null;
      final CalendarEvent? event = eventToLink(
        feed.events,
        ref.read(nowProvider)(),
      );
      return event == null ? null : _linkTo(event);
    } on Object catch (e) {
      _log.warning('Agenda illisible au démarrage (${e.runtimeType})');
      return null;
    }
  }

  /// La prochaine note démarrée se lie à [event] (celui affiché dans une
  /// suggestion) au lieu de l'événement choisi par [eventToLink].
  void linkNextNoteTo(CalendarEvent event) => _nextEvent = event;

  static SessionCalendarLink _linkTo(CalendarEvent event) =>
      SessionCalendarLink(
        eventId: event.id,
        eventTitle: event.title,
        attendees: event.attendeeNames,
      );

  /// Arrête d'attendre la fin de la transcription : le reste devient un
  /// repère de perte, l'arrêt se termine.
  void skipFinalising() => _liveService?.skipFinalising();

  /// Fin du traitement de la note : l'audio part, sauf si un rattrapage
  /// l'attend encore (GapBackfillRetry le supprime alors en lâchant la
  /// session ; un arrêt de l'app avant laisse le lancement suivant finir).
  Future<void> _finishNote(String sessionId) =>
      ref.read(gapBackfillRetryProvider).finish(sessionId);

  /// Arrete la session et sauvegarde la transcription.
  ///
  /// Renvoie l'ID de session (pour naviguer vers la fiche). Le post-traitement
  /// lourd (coach + diarization) tourne EN ARRIÈRE-PLAN : la navigation est
  /// immédiate, et la fiche détail est rafraîchie quand le traitement se
  /// termine.
  Future<String?> stopSession() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    // Capturer l'ID de session avant d'arrêter
    final String? sessionId = _liveService?.currentSessionStream.value?.id;
    final bool coachEnabled = state.isCoachEnabled;

    // Traitement de la note en cours (durable) : l'audio de la session est
    // supprimé quand il finit, ou au lancement suivant si l'app s'arrête.
    final SessionAudio audio = SessionAudio(
      LiveTranscriptionService.recordingsDir,
    );
    if (sessionId != null) audio.markProcessing(sessionId);

    // Avant le rattrapage de l'arrêt : plus rien ne part pendant
    // « Finalisation… », la réponse en vol est abandonnée.
    await _answers.stop();
    await _coach.stop();
    await _liveService?.stopTranscription();

    final List<TranscriptSegmentEntity> segments = state.segments;
    final Map<String, int> speakerLabels =
        _liveService?.speakerLabels ?? state.speakerLabels;
    // Vider les segments immédiatement — chaque session commence vierge
    state = state.copyWith(
      isRecording: false,
      isPaused: false,
      segments: <TranscriptSegmentEntity>[],
      duration: Duration.zero,
      speakerLabels: <String, int>{},
      sessionTitle: null,
    );

    // Sauvegarder la transcription en local
    await _saveTranscriptToFile(segments);

    // Interlocuteurs identifiés en direct : visibles dans la fiche de session
    // (la passe post-session, si elle tourne, les remplacera par les siens).
    if (sessionId != null) {
      await _saveLiveSpeakers(sessionId, segments, speakerLabels);
    }

    // Ce que le coach en direct a trouvé est rangé dès Arrêter : il
    // survit à un échec ou à l'arrêt de l'app pendant la passe d'après
    // l'appel (qui, si elle tourne, le reprend et complète).
    if (sessionId != null) {
      await _saveLiveCoach(sessionId, segments);
    }

    // Rafraichir la liste des sessions dans la sidebar
    await ref.read(sessionHistoryServiceProvider).loadSessions();

    // Post-traitement en arrière-plan (ne bloque pas la navigation vers la
    // fiche). Met à jour la fiche détail à la fin via invalidation.
    if (sessionId != null && coachEnabled) {
      late final Future<void> task;
      task =
          _postProcess(
                sessionId: sessionId,
                segments: segments,
                coachEnabled: coachEnabled,
              )
              .catchError((Object error, StackTrace stackTrace) {
                _log.error('Post-traitement échoué: $error');
              })
              .whenComplete(() async {
                await _finishNote(sessionId);
                if (identical(_postProcessTask, task)) _postProcessTask = null;
              });
      _postProcessTask = task;
      unawaited(task);
    } else if (sessionId != null) {
      // Pas de passe après l'appel : le traitement de la note est fini.
      await _finishNote(sessionId);
    }
    return sessionId;
  }

  /// Post-traitement séquentiel : libère le GPU, lance le coach (rapide) puis
  /// la diarization (peut télécharger un modèle au 1er lancement), et rafraîchit
  /// la fiche détail. Séquentiel pour éviter plusieurs modèles Metal en
  /// simultané (crash) et les écritures concurrentes de l'enveloppe.
  ///
  /// Le serveur de transcription (Voxtral MLX) est prêté le temps du travail :
  /// arrêté pour libérer le GPU/RAM, relancé dès la fin si la dictée est
  /// activée (une dictée demandée entre-temps attend, audio gardé).
  Future<void> _postProcess({
    required String sessionId,
    required List<TranscriptSegmentEntity> segments,
    required bool coachEnabled,
  }) => ref
      .read(dictationControllerProvider)
      .lendServer(
        () => _postProcessWork(
          sessionId: sessionId,
          segments: segments,
          coachEnabled: coachEnabled,
        ),
      );

  Future<void> _postProcessWork({
    required String sessionId,
    required List<TranscriptSegmentEntity> segments,
    required bool coachEnabled,
  }) async {
    // Coach d'abord (mistral, rapide) → trigger immédiat si activé.
    if (coachEnabled) await coachAfterCall(segments, sessionId: sessionId);

    // Le modèle Mistral était conservé cinq minutes. Le décharger avant
    // Parakeet évite de cumuler plusieurs modèles Metal en mémoire unifiée.
    try {
      await ref.read(ollamaServiceProvider).unloadModel();
    } catch (e) {
      _log.warning('Déchargement Ollama avant diarization: $e');
    }

    // Diarization + transcription propre (peut être longue la 1re fois).
    await _diarizeAndStore(sessionId);

    // Rafraîchir la fiche détail si elle est ouverte.
    ref.invalidate(sessionDetailViewModelProvider(sessionId: sessionId));
  }

  /// Lance la passe post-session (diarization + transcription propre) et
  /// fusionne le résultat dans l'enveloppe stockée. Renvoie le texte du micro.
  Future<String?> _diarizeAndStore(String? sessionId) async {
    if (sessionId == null) return null;
    try {
      final DiarizationResult? result = await ref
          .read(diarizationServiceProvider)
          .processSession(sessionId);
      if (result == null) return null;

      final SessionAnalysis existing = SessionAnalysis.fromStored(
        await ref.read(summaryServiceProvider).getSummaryForSession(sessionId),
      );
      await ref
          .read(summaryServiceProvider)
          .saveSummary(
            sessionId: sessionId,
            content: existing
                .copyWith(micText: result.micText, speakers: result.speakers)
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

  /// Moteur de cette note : le choix des réglages, si l'envoi en ligne est
  /// permis et la clé Mistral rangée ; sinon sur ce Mac.
  Future<TranscriptionEngine> _engine() async => TranscriptionEngineSelection(
    ref.read(apiKeyStoreProvider),
  ).fromPrefs(await ref.read(prefsStoreProvider).read());

  /// Interrupteurs « Coach anglais » et « Interlocuteurs en direct » rangés
  /// dans prefs.json ; défauts de l'état initial si absents ou illisibles.
  Future<void> _loadSwitches() async {
    final Map<String, Object?> prefs = await ref
        .read(prefsStoreProvider)
        .read();
    if (!ref.mounted) return;
    state = state.copyWith(
      isCoachEnabled: _coachTouched
          ? state.isCoachEnabled
          : prefValue<bool>(prefs, _coachKey) ?? state.isCoachEnabled,
      isLiveSpeakersEnabled: _speakersTouched
          ? state.isLiveSpeakersEnabled
          : prefValue<bool>(prefs, _speakersKey) ?? state.isLiveSpeakersEnabled,
      isLiveCoachEnabled: _liveCoachTouched
          ? state.isLiveCoachEnabled
          : prefValue<bool>(prefs, _liveCoachKey) ?? state.isLiveCoachEnabled,
    );
  }

  /// Active ou désactive le coach d'anglais.
  void toggleCoach() {
    _coachTouched = true;
    state = state.copyWith(isCoachEnabled: !state.isCoachEnabled);
    unawaited(
      ref.read(prefsStoreProvider).update(<String, Object?>{
        _coachKey: state.isCoachEnabled,
      }),
    );
  }

  /// Active ou désactive le coach anglais en direct (pris en compte au
  /// prochain enregistrement).
  void toggleLiveCoach() {
    _liveCoachTouched = true;
    state = state.copyWith(isLiveCoachEnabled: !state.isLiveCoachEnabled);
    unawaited(
      ref.read(prefsStoreProvider).update(<String, Object?>{
        _liveCoachKey: state.isLiveCoachEnabled,
      }),
    );
  }

  /// Active ou désactive l'identification des interlocuteurs en direct.
  void toggleLiveSpeakers() {
    _speakersTouched = true;
    state = state.copyWith(isLiveSpeakersEnabled: !state.isLiveSpeakersEnabled);
    unawaited(
      ref.read(prefsStoreProvider).update(<String, Object?>{
        _speakersKey: state.isLiveSpeakersEnabled,
      }),
    );
  }

  /// Enregistre les tours de parole identifiés en direct dans l'enveloppe
  /// d'analyse de la session (mêmes champs que la passe post-session).
  Future<void> _saveLiveSpeakers(
    String sessionId,
    List<TranscriptSegmentEntity> segments,
    Map<String, int> labels,
  ) async {
    final List<SpeakerTurn> turns = buildSpeakerTurns(segments, labels);
    if (turns.isEmpty) return;
    try {
      final SessionAnalysis existing = SessionAnalysis.fromStored(
        await ref.read(summaryServiceProvider).getSummaryForSession(sessionId),
      );
      if (existing.speakers.isNotEmpty) return;
      await ref
          .read(summaryServiceProvider)
          .saveSummary(
            sessionId: sessionId,
            content: existing.copyWith(speakers: turns).toStored(),
          );
      _log.info('Interlocuteurs en direct stockés: ${turns.length} tours');
    } catch (e) {
      _log.warning('Sauvegarde des interlocuteurs en direct échouée: $e');
    }
  }

  /// Active/désactive la traduction temps réel.
  void toggleTranslation() {
    final bool enabled = !state.isTranslationEnabled;
    _translationGeneration++;
    _cancelTranslationDebounces();
    state = state.copyWith(
      isTranslationEnabled: enabled,
      translations: enabled ? state.translations : <String, String>{},
    );
    if (enabled) {
      unawaited(_prepareTranslationPair());
      _translateNewSegments(state.segments);
    }
  }

  /// Change les langues de traduction et retraduit.
  void setTranslationLangs({String? from, String? to}) {
    _translationGeneration++;
    _cancelTranslationDebounces();
    state = state.copyWith(
      translationFrom: from ?? state.translationFrom,
      translationTo: to ?? state.translationTo,
      translations: <String, String>{},
    );
    if (state.isTranslationEnabled) {
      unawaited(_prepareTranslationPair());
      _translateNewSegments(state.segments);
    }
  }

  /// Traduit les nouveaux segments finalisés (par phrase, en tâche de fond).
  void _translateNewSegments(List<TranscriptSegmentEntity> segments) {
    if (!state.isTranslationEnabled) return;
    final String from = state.translationFrom;
    final String to = state.translationTo;
    final int generation = _translationGeneration;
    final Set<String> activeIds = segments
        .map((TranscriptSegmentEntity segment) => segment.id)
        .toSet();
    for (final String id in _translateDebounces.keys.toList()) {
      if (id.startsWith('current_') && !activeIds.contains(id)) {
        _translateDebounces.remove(id)?.cancel();
      }
    }

    // Chaque segment a sa propre traduction, clé = id du segment (les ids des
    // phrases en cours sont stables : "current_input" / "current_output").
    for (final TranscriptSegmentEntity s in segments) {
      final bool inProgress = s.id.startsWith('current_');
      if (inProgress) {
        // Phrase en cours : traduire en direct (debounce par source), réécrit
        // au fil de la croissance du texte.
        final String text = s.text;
        final String id = s.id;
        _translateDebounces[id]?.cancel();
        _translateDebounces[id] = Timer(const Duration(milliseconds: 900), () {
          _translateDebounces.remove(id);
          if (!_translationRequestIsCurrent(generation, from, to)) return;
          ref
              .read(translationServiceProvider)
              .translate(text: text, from: from, to: to)
              .then((String t) {
                if (t.isEmpty ||
                    !_translationRequestIsCurrent(generation, from, to)) {
                  return;
                }
                final TranscriptSegmentEntity? current = _segmentById(id);
                if (current == null || current.text != text) return;
                state = state.copyWith(
                  translations: <String, String>{...state.translations, id: t},
                );
              });
        });
      } else {
        // Phrase finalisée : traduire une seule fois.
        if (state.translations.containsKey(s.id)) continue;
        state = state.copyWith(
          translations: <String, String>{...state.translations, s.id: ''},
        );
        final String id = s.id;
        ref
            .read(translationServiceProvider)
            .translate(text: s.text, from: from, to: to)
            .then((String t) {
              if (!_translationRequestIsCurrent(generation, from, to)) {
                return;
              }
              if (t.isEmpty) {
                final Map<String, String> translations = <String, String>{
                  ...state.translations,
                }..remove(id);
                state = state.copyWith(translations: translations);
                final int attempts = _translationRetries[id] ?? 0;
                if (attempts < 1) {
                  _translationRetries[id] = attempts + 1;
                  final String timerId = 'retry:$id';
                  _translateDebounces[timerId]?.cancel();
                  _translateDebounces[timerId] = Timer(
                    const Duration(seconds: 2),
                    () {
                      _translateDebounces.remove(timerId);
                      if (_translationRequestIsCurrent(generation, from, to) &&
                          _segmentById(id) != null) {
                        _translateNewSegments(state.segments);
                      }
                    },
                  );
                }
                return;
              }
              _translationRetries.remove(id);
              state = state.copyWith(
                translations: <String, String>{...state.translations, id: t},
              );
            });
      }
    }
  }

  bool _translationRequestIsCurrent(int generation, String from, String to) =>
      generation == _translationGeneration &&
      state.isTranslationEnabled &&
      state.translationFrom == from &&
      state.translationTo == to;

  TranscriptSegmentEntity? _segmentById(String id) {
    for (final TranscriptSegmentEntity segment in state.segments) {
      if (segment.id == id) return segment;
    }
    return null;
  }

  void _cancelTranslationDebounces() {
    for (final Timer timer in _translateDebounces.values) {
      timer.cancel();
    }
    _translateDebounces.clear();
    _translationRetries.clear();
  }

  Future<void> _prepareTranslationPair() async {
    final int generation = _translationGeneration;
    final String from = state.translationFrom;
    final String to = state.translationTo;
    final bool ready = await ref
        .read(translationServiceProvider)
        .preparePair(from: from, to: to);
    if (!ready && _translationRequestIsCurrent(generation, from, to)) {
      _log.warning('Paire de traduction indisponible: $from->$to');
    }
  }

  /// Met en pause.
  Future<void> pauseSession() async {
    try {
      _answers.pause();
      await _liveService?.pauseTranscription();
      _durationTimer?.cancel();
      state = state.copyWith(isPaused: true);
    } catch (e) {
      _log.error('Mise en pause échouée: $e');
    }
  }

  /// Reprend.
  Future<void> resumeSession() async {
    try {
      await _liveService?.resumeTranscription();
      _answers.resume();
      state = state.copyWith(isPaused: false);
      _startDurationTimer();
    } catch (e) {
      _log.error('Reprise échouée: $e');
    }
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
      final Directory dir = Directory('${appDataDirectory()}/transcripts');
      await dir.create(recursive: true);

      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File('${dir.path}/transcript_$timestamp.txt');

      final StringBuffer buffer = StringBuffer();
      for (final TranscriptSegmentEntity segment in segments) {
        buffer.writeln(TranscriptFormatter.plainLine(segment));
      }

      await file.writeAsString(buffer.toString());
      _log.info('Transcription sauvegardee: ${file.path}');
    } catch (e) {
      _log.error('Erreur sauvegarde transcription: $e');
    }
  }

  /// Ce que le coach en direct a trouvé pour [sessionId] (rien s'il a
  /// tourné pour une autre note).
  ({List<EnglishCorrectionEntity> found, Set<String> coached}) _liveFor(
    String? sessionId,
  ) {
    final LiveCoachService live = _coach;
    if (sessionId == null || live.snapshot.sessionId != sessionId) {
      return (found: const <EnglishCorrectionEntity>[], coached: <String>{});
    }
    return (found: live.snapshot.corrections, coached: live.coachedSegmentIds);
  }

  /// Range ce que le coach en direct a trouvé pour [sessionId] (s'il a
  /// analysé au moins une phrase) ; les phrases de [segments] qu'il n'a pas
  /// analysées sont dites non analysées (jamais un faux « impeccable »).
  Future<void> _saveLiveCoach(
    String sessionId,
    List<TranscriptSegmentEntity> segments,
  ) async {
    final ({List<EnglishCorrectionEntity> found, Set<String> coached}) live =
        _liveFor(sessionId);
    if (live.coached.isEmpty) return;
    try {
      await _saveFeedback(
        sessionId,
        EnglishFeedbackEntity(
          corrections: live.found,
          unanalyzedSegmentIds: <String>[
            for (final TranscriptSegmentEntity s in coachableLines(
              segments,
              skip: live.coached,
            ))
              s.id,
          ],
        ),
      );
    } on Object catch (e) {
      _log.warning('Sauvegarde du coach en direct échouée : $e');
    }
  }

  /// Range [feedback] dans l'enveloppe partagée (résumé + coach) ; le
  /// modèle rangé reste celui du résumé.
  Future<void> _saveFeedback(
    String sessionId,
    EnglishFeedbackEntity feedback,
  ) async {
    final SessionAnalysis existing = SessionAnalysis.fromStored(
      await ref.read(summaryServiceProvider).getSummaryForSession(sessionId),
    );
    await ref
        .read(summaryServiceProvider)
        .saveSummary(
          sessionId: sessionId,
          content: existing.copyWith(feedback: feedback).toStored(),
        );
  }

  /// Coach d'après l'appel, par le fournisseur actif : les phrases
  /// anglaises de l'utilisateur dans [segments], sauf celles déjà corrigées
  /// en direct pour cette note ; le retour (direct + après l'appel) est
  /// rangé, quel qu'il soit. Tout en échec : rangé quand même, toutes les
  /// phrases non analysées (la note propose de réessayer).
  ///
  /// Rien d'utilisable (envoi coupé ou sans clé, modèle local absent) : rien
  /// n'est envoyé ni téléchargé ; seul le direct est rangé.
  @visibleForTesting
  Future<void> coachAfterCall(
    List<TranscriptSegmentEntity> segments, {
    String? sessionId,
  }) async {
    final ({List<EnglishCorrectionEntity> found, Set<String> coached}) live =
        _liveFor(sessionId);
    final List<TranscriptSegmentEntity> lines = coachableLines(
      segments,
      skip: live.coached,
    );
    if (lines.isEmpty) {
      if (sessionId == null) return;
      if (live.coached.isEmpty && coachableLines(segments).isEmpty) {
        // Aucune phrase anglaise de l'utilisateur : la note le dit.
        const EnglishFeedbackEntity nothing = EnglishFeedbackEntity(
          nothingToAnalyse: true,
        );
        if (ref.mounted) state = state.copyWith(feedback: nothing);
        await _saveFeedback(sessionId, nothing);
      } else {
        await _saveLiveCoach(sessionId, segments);
      }
      return;
    }
    state = state.copyWith(isFeedbackLoading: true);
    EnglishFeedbackEntity feedback;
    try {
      final ReadyLlm? ready = await readyLlm(ref);
      if (ready == null) {
        _log.info('Coach ignoré : aucun modèle utilisable');
        if (ref.mounted) state = state.copyWith(isFeedbackLoading: false);
        if (sessionId != null) await _saveLiveCoach(sessionId, segments);
        return;
      }
      final EnglishFeedbackEntity after = await coachMeeting(
        ready.llm,
        segments,
        skipSegmentIds: live.coached,
        shouldStop: _recordingWanted,
      );
      feedback = after.copyWith(
        corrections: mergeCorrections(live.found, after.corrections),
      );
      _log.info(
        'Analyse anglais terminée (${feedback.corrections.length} corrections)',
      );
    } on Object catch (e) {
      _log.error('Coach anglais échoué : $e');
      feedback = EnglishFeedbackEntity(
        corrections: live.found,
        unanalyzedSegmentIds: <String>[
          for (final TranscriptSegmentEntity s in lines) s.id,
        ],
      );
    }
    if (ref.mounted) {
      state = state.copyWith(isFeedbackLoading: false, feedback: feedback);
    }
    if (sessionId == null) return;
    try {
      await _saveFeedback(sessionId, feedback);
      _log.info('Retour coach sauvegardé pour session $sessionId');
    } on Object catch (e) {
      _log.error('Sauvegarde du retour coach échouée : $e');
    }
  }
}
