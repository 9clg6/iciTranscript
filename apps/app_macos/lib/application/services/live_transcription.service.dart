import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart' as data;
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/transcription_health.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_diarization.service.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';
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
///
/// Réunions longues : l'audio de chaque source est toujours enregistré en
/// WAV, la phrase en cours est sauvée au fil de l'eau, un crash du serveur
/// ML le relance (délai croissant, puis abandon signalé par
/// [transcriptionHealthStream]) sans couper l'enregistrement, et toute perte
/// d'audio réelle laisse un repère horodaté dans la transcription.
final class LiveTranscriptionService {
  /// Cree une instance de [LiveTranscriptionService].
  LiveTranscriptionService({
    required ProcessManagerService processManagerService,
    required AudioCaptureChannel audioCaptureChannel,
    required TranscriptionRemoteDataSource transcriptionRemoteDataSource,
    required TranscriptionService transcriptionService,
    LiveDiarizationService? liveDiarization,
    WavRecorder Function()? createWavRecorder,
    GapBackfillService? gapBackfill,
    GapBackfillRetry? gapBackfillRetry,
    ServerPorts? ports,
  }) : _gapBackfill = gapBackfill,
       _gapBackfillRetry = gapBackfillRetry,
       _ports = ports ?? serverPorts(),
       _processManagerService = processManagerService,
       _audioCaptureChannel = audioCaptureChannel,
       _transcriptionRemoteDataSource = transcriptionRemoteDataSource,
       _transcriptionService = transcriptionService,
       _liveDiarization = liveDiarization,
       _createWavRecorder = createWavRecorder ?? WavRecorder.new;

  final ServerPorts _ports;
  final ProcessManagerService _processManagerService;
  final AudioCaptureChannel _audioCaptureChannel;
  final TranscriptionRemoteDataSource _transcriptionRemoteDataSource;
  final TranscriptionService _transcriptionService;
  final LiveDiarizationService? _liveDiarization;
  final WavRecorder Function() _createWavRecorder;
  final GapBackfillService? _gapBackfill;
  // Si présent, la première tentative passe par lui : un serveur absent
  // laisse la session en attente de reprise.
  final GapBackfillRetry? _gapBackfillRetry;

  // Interlocuteurs en direct : id de segment système -> index (0, 1, …).
  final BehaviorSubject<Map<String, int>> _speakerLabels =
      BehaviorSubject<Map<String, int>>.seeded(<String, int>{});
  final List<_PendingLabel> _pendingLabels = <_PendingLabel>[];
  StreamSubscription<void>? _diarizationUpdates;
  Timer? _labelTimer;
  bool _liveDiarizationEnabled = false;

  final Log _log = Log.named('LiveTranscriptionService');

  StreamSubscription<data.AudioChunk>? _audioSubscription;
  StreamSubscription<TranscriptEventRemoteModel>? _transcriptionSubscription;
  StreamSubscription<TranscriptEventRemoteModel>?
  _systemTranscriptionSubscription;
  final Set<Future<void>> _pendingFinalizations = <Future<void>>{};
  final Map<AudioSource, Completer<void>> _stopFinalizationWaiters =
      <AudioSource, Completer<void>>{};
  Future<void> _lifecycleTail = Future<void>.value();

  // Enregistrement des flux bruts, pour chaque session : trace de la réunion
  // si le texte en direct manque, et passe post-session (Path B) :
  // micro = MOI, système = interlocuteurs (diarization).
  WavRecorder? _micRecorder;
  WavRecorder? _systemRecorder;
  String? _captureInputDeviceId;
  bool _captureOutputEnabled = false;
  bool _capturePaused = false;
  int _audioChunkCount = 0;

  /// Dossier des WAV de session (réparés au lancement, voir kernel).
  static String get recordingsDir => '${appDataDirectory()}/recordings';

  // Supervision du serveur ML pendant une session : relance après 2, 4, 8…
  // 64 s, puis abandon. Le compteur ne repart à zéro qu'après une minute de
  // marche, sinon un serveur qui retombe aussitôt serait relancé sans fin.
  static const String _readyPattern = 'VOXMLX_READY';
  static const int _maxServerRestarts = 6;
  static const Duration _firstRestartDelay = Duration(seconds: 2);
  static const Duration _stableServerUptime = Duration(minutes: 1);
  String _serverCommand = 'voxmlx-serve';
  List<String> _serverArgs = const <String>[];
  StreamSubscription<ServerState>? _serverStateSubscription;
  StreamSubscription<domain.ConnectionState>? _connectionSubscription;
  StreamSubscription<AudioGap>? _gapSubscription;
  Timer? _restartTimer;
  Timer? _stableTimer;
  bool _restartInFlight = false;
  bool _restartsExhausted = false;
  // Faux dès qu'un arrêt est demandé : aucune relance ne part ensuite.
  bool _supervising = false;
  int _restartAttempts = 0;
  domain.ConnectionState _remoteState = domain.ConnectionState.connected;
  final BehaviorSubject<TranscriptionHealth> _health =
      BehaviorSubject<TranscriptionHealth>.seeded(TranscriptionHealth.healthy);

  /// Santé de la transcription en direct (l'enregistrement continue
  /// toujours, même en [TranscriptionHealth.failed]).
  Stream<TranscriptionHealth> get transcriptionHealthStream => _health.stream;

  // Arrêt : attendre le rattrapage étalé (sonde 2 : 29 s et 103 s après la
  // fin de l'audio), au plus [_stopDrainLimit] ; une pause n'attend que
  // [_pauseDrainLimit]. Ce qui reste devient une perte signalée.
  static const Duration _stopDrainLimit = Duration(seconds: 120);
  static const Duration _pauseDrainLimit = Duration(seconds: 5);
  final PublishSubject<Duration> _finalisingRemaining =
      PublishSubject<Duration>();
  // Signal « Passer » de l'arrêt en cours : vaut pour l'attente du
  // rattrapage comme pour le rattrapage depuis le WAV.
  Completer<void>? _skipStop;

  // Démarrage demandé (pas encore fini) : le serveur est réservé à
  // l'enregistrement dès cet instant (le rattrapage cède), et un arrêt en
  // cours passe sa finalisation.
  bool _startRequested = false;
  // Session réellement démarrée (et pas encore arrêtée).
  bool _running = false;

  /// Audio restant à transcrire pendant l'attente de l'arrêt (décroissant),
  /// puis [Duration.zero] : de quoi afficher « finalisation… ».
  Stream<Duration> get finalisingRemainingStream => _finalisingRemaining.stream;

  /// Session réellement démarrée (capture et flux ouverts), pas seulement
  /// demandée ni en cours d'arrêt.
  bool get isRunning => _running;

  /// Démarrage demandé, capture pas encore ouverte.
  bool get isStarting => _startRequested && !_running;

  /// Fin des démarrages et arrêts déjà demandés (vidange comprise).
  Future<void> whenIdle() => _lifecycleTail.catchError((Object _) {});

  /// Appelé au début de chaque démarrage, avant le serveur et la capture :
  /// une dictée hors réunion se termine d'abord (jamais deux captures ni
  /// trois flux).
  Future<void> Function()? recordingHandover;

  /// Arrête d'attendre le rattrapage : l'audio restant devient une perte
  /// signalée (repère), l'arrêt se termine aussitôt.
  void skipFinalising() {
    final Completer<void>? skip = _skipStop;
    if (skip != null && !skip.isCompleted) skip.complete();
  }

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

  /// Interlocuteur de chaque segment système (id -> 0, 1, …), en direct.
  Stream<Map<String, int>> get speakerLabelsStream => _speakerLabels.stream;

  /// Statut de la capture audio (ex. son du Mac indisponible).
  Stream<Map<String, String>> get captureStatusStream =>
      _audioCaptureChannel.statusStream;

  /// Dernières étiquettes connues.
  Map<String, int> get speakerLabels => _speakerLabels.value;

  /// Vérifie les statuts de permissions (micro + Screen Recording).
  Future<Map<String, String>> checkPermissions() =>
      _audioCaptureChannel.checkPermissions();

  /// Ouvre le panneau de permissions dans les Réglages Système.
  Future<void> openSystemSettings(String pane) =>
      _audioCaptureChannel.openSystemSettings(pane);

  /// Demarre une session de transcription en direct.
  ///
  /// [enablePostProcessing] n'influe plus sur l'enregistrement : l'audio
  /// est toujours enregistré.
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
    String? webSocketUrl,
    bool enablePostProcessing = false,
    bool liveDiarization = false,
  }) {
    // Dès la demande : l'enregistrement a la priorité sur le serveur
    // (séquentiel). Le prédicat « enregistrement » lu par le rattrapage
    // devient vrai tout de suite, et la finalisation d'une réunion
    // précédente passe à son repère au lieu de retarder celle-ci.
    _startRequested = true;
    _transcriptionService.isTranscribingStream.add(true);
    skipFinalising();
    return _serializeLifecycle(
      () => _startTranscription(
        inputDeviceId: inputDeviceId,
        outputEnabled: outputEnabled,
        serverCommand: serverCommand,
        serverArgs: serverArgs,
        webSocketUrl: webSocketUrl ?? '${_ports.transcriptionWebSocket}',
        liveDiarization: liveDiarization,
      ),
    ).whenComplete(() => _startRequested = false);
  }

  Future<void> _startTranscription({
    required String? inputDeviceId,
    required bool outputEnabled,
    required String serverCommand,
    required List<String> serverArgs,
    required String webSocketUrl,
    required bool liveDiarization,
  }) async {
    if (_running) {
      _log.warning('Une transcription est déjà en cours');
      return;
    }
    try {
      await recordingHandover?.call();
    } catch (e) {
      _log.warning('Fin de la dictée avant l enregistrement: $e');
    }
    try {
      _log.info('=== DEMARRAGE TRANSCRIPTION ===');
      _captureInputDeviceId = inputDeviceId;
      _captureOutputEnabled = outputEnabled;
      _capturePaused = false;
      _audioChunkCount = 0;
      _serverCommand = serverCommand;
      _serverArgs = serverArgs;
      _resetServerSupervision();
      _supervising = true;

      // 1. Demarrer le serveur ML si pas deja en cours
      final bool serverRunning = await _processManagerService.isServerRunning();
      if (!serverRunning) {
        _log.info('Demarrage du serveur ML: $serverCommand');
        await _processManagerService.startServer(
          command: serverCommand,
          args: serverArgs,
          readyPattern: _readyPattern,
        );
        _log.info('Serveur ML demarre OK');
      } else {
        _log.info('Serveur ML deja en cours');
      }
      _serverStateSubscription = _processManagerService.stateStream.listen(
        _onServerState,
      );

      // 2. Connexion WebSocket (la source distante se reconnecte seule).
      _connectionSubscription = _transcriptionRemoteDataSource.connectionState
          .listen((domain.ConnectionState state) {
            _remoteState = state;
            _updateHealth();
          });
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

      // 4b. Ouvrir les enregistreurs WAV par session (micro + système) :
      // toujours, l'audio reste même si la transcription en direct échoue.
      final String? recSessionId = currentSessionStream.valueOrNull?.id;
      if (recSessionId != null) {
        try {
          _micRecorder = _createWavRecorder();
          _systemRecorder = _createWavRecorder();
          await _micRecorder!.open('$recordingsDir/${recSessionId}_mic.wav');
          await _systemRecorder!.open(
            '$recordingsDir/${recSessionId}_system.wav',
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
      _gapSubscription = _transcriptionRemoteDataSource.audioGaps.listen(
        _onAudioGap,
      );

      // 5b. Interlocuteurs en direct (audio système) : démarre en arrière-plan,
      // la transcription n'attend pas le serveur (premier lancement : modèle).
      _speakerLabels.add(<String, int>{});
      _pendingLabels.clear();
      _liveDiarizationEnabled =
          liveDiarization && outputEnabled && _liveDiarization != null;
      if (_liveDiarizationEnabled) _startLiveDiarization();

      // 6. Relayer l'audio vers le WebSocket.
      _subscribeToAudio();
      _log.info('Audio subscription active, en attente de chunks...');
      _running = true;
      _provisionalTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateProvisionalMarkers(),
      );

      _log.info('=== TRANSCRIPTION EN DIRECT DEMARREE ===');
    } catch (e, st) {
      _log.error('Erreur demarrage transcription', e);
      _log.error('Stack: $st');
      await _stopTranscription();
      _transcriptionService.isTranscribingStream.add(false);
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
    _cancel(_audioSubscription);
    _audioSubscription = null;
    await _audioCaptureChannel.stopCapture();
    await _flushRemoteTranscripts(limit: _pauseDrainLimit);
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
      _cancel(_audioSubscription);
      _audioSubscription = null;
      rethrow;
    }
  }

  Future<void> _stopTranscription() async {
    _log.info('Arret de la transcription en direct');
    _running = false;
    // Dictée en cours : fin comme un relâchement (son texte vient du flush).
    final MeetingDictation? open = _openDictation;
    if (open != null) _endDictation(open, cancelled: false);
    _draining = true;
    final Completer<void> skip = _skipStop = Completer<void>();
    // Un démarrage déjà demandé : pas d'attente, droit au repère.
    if (_startRequested) skip.complete();
    _supervising = false;
    _resetServerSupervision();
    _cancel(_serverStateSubscription);
    _serverStateSubscription = null;

    // Couper d'abord la capture afin que plus aucun chunk ne soit ajouté pendant
    // la finalisation des deux sessions voxmlx.
    _cancel(_audioSubscription);
    _audioSubscription = null;
    try {
      await _audioCaptureChannel.stopCapture();
    } catch (e) {
      _log.warning('Arrêt capture audio: $e');
    }

    // Demander un vrai flush serveur et laisser les listeners recevoir les
    // derniers deltas + `done`, rattrapage compris (borné, passable). Le
    // reste devient une perte au disconnect() ; les deltas restent en repli.
    await _flushRemoteTranscripts(
      limit: _stopDrainLimit,
      publish: true,
      skip: skip.future,
    );

    // Plus aucun `done` de dictée ne viendra : chacune rend ce qu'elle a.
    for (final MeetingDictation d in _dictations) {
      d._finish();
    }
    _dictations.clear();

    // Plus aucun événement distant après ce point : cela évite qu'un `done`
    // tardif duplique le fallback local.
    _cancel(_transcriptionSubscription);
    _transcriptionSubscription = null;
    _cancel(_systemTranscriptionSubscription);
    _systemTranscriptionSubscription = null;
    _stopFinalizationWaiters.clear();
    for (final Timer timer in _checkpointTimers.values) {
      timer.cancel();
    }
    _checkpointTimers.clear();

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

    // Dernières trames de diarization, puis étiquetage des phrases restantes
    // et arrêt du serveur (libère la mémoire avant la passe post-session).
    await _stopLiveDiarization();

    // Finaliser les enregistrements WAV (corrige l'en-tête).
    try {
      await _micRecorder?.close();
      await _systemRecorder?.close();
    } catch (e) {
      _log.warning('Fermeture enregistreurs WAV: $e');
    }
    _micRecorder = null;
    _systemRecorder = null;
    _capturePaused = false;
    _captureInputDeviceId = null;
    _captureOutputEnabled = false;

    // Deconnecte le WebSocket. L'audio encore en tampon de coupure est perdu
    // pour la transcription : la perte arrive par `audioGaps` et son repère
    // doit être sauvé avant de clore la session.
    await _transcriptionRemoteDataSource.disconnect();
    // ponytail: un tour de boucle suffit à livrer la perte (PublishSubject
    // asynchrone). Faire rendre les pertes par disconnect() si cela change.
    await Future<void>.delayed(Duration.zero);
    if (_pendingFinalizations.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.from(_pendingFinalizations));
    }
    _cancel(_gapSubscription);
    _gapSubscription = null;
    _cancel(_connectionSubscription);
    _connectionSubscription = null;
    // Tout est livré ou signalé par un vrai repère : plus de provisoire.
    _provisionalTimer?.cancel();
    _provisionalTimer = null;
    _draining = false;
    await _clearProvisionalMarkers();

    // Arreter la session
    final String? closedSessionId = currentSessionStream.valueOrNull?.id;
    await _transcriptionService.stopSession();
    // stopSession() remet le prédicat à faux : un démarrage demandé entre-
    // temps doit le garder vrai (aucun rattrapage ne doit partir).
    if (_startRequested) _transcriptionService.isTranscribingStream.add(true);

    // Session close (l'écran le voit déjà) : ses repères de perte sont
    // retranscrits depuis les WAV AVANT de rendre la main, car la passe
    // post-session qui suit supprime ces WAV. Sans repère, rien n'attend.
    if (closedSessionId != null) await _backfillGaps(closedSessionId, skip);
    _skipStop = null;

    _log.info('Transcription en direct arretee');
  }

  // Borne du rattrapage à l'arrêt ; au-delà, les repères restent (journal).
  static const Duration _backfillLimit = Duration(minutes: 5);

  Future<void> _backfillGaps(String sessionId, Completer<void> skip) async {
    final GapBackfillService? backfill = _gapBackfill;
    final GapBackfillRetry? retry = _gapBackfillRetry;
    if (backfill == null && retry == null) return;
    final List<({String markerId, AudioSource source, int startMs, int endMs})>
    plan = GapBackfillService.plan(
      segmentsStream.value
          .where((TranscriptSegmentEntity s) => s.sessionId == sessionId)
          .toList(),
      dictated: DictatedIntervalsStore(recordingsDir).read(sessionId),
    );
    if (plan.isEmpty) return;
    if (_startRequested || skip.isCompleted) {
      // Un enregistrement arrive (ou l'utilisateur a passé) : la session est
      // mise en attente de reprise, sans tentative ; le repère reste.
      await retry?.enqueue(sessionId);
      return;
    }
    // Même flux que l'attente du rattrapage : « transcription en cours
    // d'achèvement », puis zéro.
    _finalisingRemaining.add(
      plan.fold<Duration>(
        Duration.zero,
        (
          Duration sum,
          ({String markerId, AudioSource source, int startMs, int endMs}) g,
        ) => sum + Duration(milliseconds: g.endMs - g.startMs),
      ),
    );
    // « Passer » rend la main tout de suite ; le rattrapage continue en
    // tâche de fond (ou sera réessayé), le repère reste jusqu'à son
    // remplacement.
    final Future<void> work =
        (retry != null
                ? retry.afterSession(sessionId)
                : backfill!.backfill(
                    sessionId,
                    recordingsDirectory: recordingsDir,
                  ))
            .timeout(_backfillLimit)
            .then<void>((_) {})
            .catchError((Object e) {
              _log.warning('Rattrapage des repères interrompu: $e');
            });
    try {
      await Future.any<void>(<Future<void>>[work, skip.future]);
    } finally {
      _finalisingRemaining.add(Duration.zero);
    }
  }

  // ---------------------------------------------------------------------------
  // Repère provisoire : audio en attente (coupure, ou arrêt qui attend le
  // rattrapage) écrit en base tout de suite, pour qu'un arrêt brutal de l'app
  // laisse de quoi rattraper depuis le WAV au lancement suivant.
  // ---------------------------------------------------------------------------

  Timer? _provisionalTimer;
  bool _draining = false;
  final Map<AudioSource, String> _provisionalMarkers = <AudioSource, String>{};
  Future<void> _markerWrites = Future<void>.value();

  String _provisionalMarkerId(SessionEntity session, AudioSource source) =>
      '${session.id}_${source.name}_pending';

  void _updateProvisionalMarkers() {
    final TranscriptionRemoteDataSource remote = _transcriptionRemoteDataSource;
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (remote is! TranscriptionRemoteDataSourceImpl || session == null) return;
    for (final AudioSource source in AudioSource.values) {
      final ({int startMs, int endMs})? range = remote.pendingRange(source);
      final bool waiting =
          remote.bufferedAudio(source) >= const Duration(seconds: 1) ||
          (_draining && remote.unacknowledgedAudio(source) > Duration.zero);
      final String id = _provisionalMarkerId(session, source);
      if (waiting && range != null) {
        final int start = _offsetOf(session, range.startMs);
        final String text = gapMarkerText(
          start,
          _offsetOf(session, range.endMs),
        );
        if (_provisionalMarkers[source] == text) continue;
        _provisionalMarkers[source] = text;
        final TranscriptSegmentEntity marker = TranscriptSegmentEntity(
          id: id,
          sessionId: session.id,
          source: source,
          text: text,
          timestampMs: start,
          createdAt: clock.now(),
        );
        _markerWrites = _markerWrites.then(
          (_) => _transcriptionService.saveProvisional(marker),
        );
      } else if (_provisionalMarkers.remove(source) != null) {
        _markerWrites = _markerWrites.then(
          (_) => _transcriptionService.discardProvisional(id),
        );
      }
    }
  }

  Future<void> _clearProvisionalMarkers() async {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (session != null) {
      for (final AudioSource source in _provisionalMarkers.keys.toList()) {
        final String id = _provisionalMarkerId(session, source);
        _markerWrites = _markerWrites.then(
          (_) => _transcriptionService.discardProvisional(id),
        );
      }
    }
    _provisionalMarkers.clear();
    await _markerWrites;
  }

  /// Libere les ressources du service.
  Future<void> dispose() async {
    _resetServerSupervision();
    await _serverStateSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _gapSubscription?.cancel();
    for (final Timer timer in _checkpointTimers.values) {
      timer.cancel();
    }
    _labelTimer?.cancel();
    await _diarizationUpdates?.cancel();
    await _liveDiarization?.stop();
    await _audioSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
    await _systemTranscriptionSubscription?.cancel();
    await _health.close();
    await _finalisingRemaining.close();
  }

  // ---------------------------------------------------------------------------
  // Supervision du serveur ML
  // ---------------------------------------------------------------------------

  void _resetServerSupervision() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _restartInFlight = false;
    _restartsExhausted = false;
    _restartAttempts = 0;
    _remoteState = domain.ConnectionState.connected;
    _updateHealth();
  }

  bool get _restartPending =>
      _restartInFlight || (_restartTimer?.isActive ?? false);

  void _onServerState(ServerState state) {
    // Un démarrage raté émet aussi `error` : une seule relance à la fois.
    if (!_supervising || !isRecording || state != ServerState.error) return;
    if (_restartPending || _restartsExhausted) return;
    _log.warning('Serveur ML tombé en pleine session, relance');
    _stableTimer?.cancel();
    _scheduleServerRestart();
  }

  void _scheduleServerRestart() {
    if (_restartAttempts >= _maxServerRestarts) {
      _restartsExhausted = true;
      _log.error(
        'Serveur ML : $_restartAttempts relances sans succès, abandon. '
        "L'enregistrement continue.",
      );
      _updateHealth();
      return;
    }
    _restartTimer = Timer(
      _firstRestartDelay * (1 << _restartAttempts),
      () => unawaited(_restartServer()),
    );
    _updateHealth();
  }

  // Hors de _serializeLifecycle : un modèle qui recharge (minutes) ne doit
  // pas bloquer l'arrêt demandé par l'utilisateur.
  Future<void> _restartServer() async {
    if (!_supervising || !isRecording) return;
    _restartInFlight = true;
    _restartAttempts++;
    _updateHealth();
    try {
      await _processManagerService.startServer(
        command: _serverCommand,
        args: _serverArgs,
        readyPattern: _readyPattern,
      );
    } catch (e) {
      _log.warning('Relance du serveur ML échouée: $e');
      _restartInFlight = false;
      if (_supervising && isRecording) _scheduleServerRestart();
      return;
    }
    _restartInFlight = false;
    if (!_supervising || !isRecording) return;
    _log.info('Serveur ML relancé');
    _stableTimer = Timer(_stableServerUptime, () => _restartAttempts = 0);
    _updateHealth();
  }

  void _updateHealth() {
    // `error` de la source distante : serveur muet malgré les reprises, la
    // perte est signalée ; l'enregistrement continue.
    final TranscriptionHealth next =
        _restartsExhausted || _remoteState == domain.ConnectionState.error
        ? TranscriptionHealth.failed
        : _restartPending || _remoteState != domain.ConnectionState.connected
        ? TranscriptionHealth.recovering
        : TranscriptionHealth.healthy;
    if (!_health.isClosed && _health.value != next) _health.add(next);
  }

  /// Début du texte d'un repère de perte (lu par GapBackfillService).
  static const String gapMarkerPrefix = 'Transcription interrompue';

  /// Repère d'une perte d'audio, en heures:minutes:secondes de réunion.
  static String gapMarkerText(int startMs, int endMs) =>
      '$gapMarkerPrefix : ${TranscriptFormatter.timestamp(startMs)} '
      '– ${TranscriptFormatter.timestamp(endMs)}';

  void _onAudioGap(AudioGap gap) {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (session == null) return;
    final int startMs = _offsetOf(session, gap.startMs);
    final TranscriptSegmentEntity marker = TranscriptSegmentEntity(
      id: _newSegmentId(session, gap.source),
      sessionId: session.id,
      source: gap.source,
      text: gapMarkerText(startMs, _offsetOf(session, gap.endMs)),
      timestampMs: startMs,
      createdAt: clock.now(),
    );
    _log.warning('Audio non transcrit: ${marker.text} (${gap.source.name})');
    late final Future<void> task;
    task = _transcriptionService
        .saveSegment(marker)
        .then((_) => _sortAndDedupeSegments())
        .whenComplete(() => _pendingFinalizations.remove(task));
    _pendingFinalizations.add(task);
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Annule sans attendre : l'annulation prend effet tout de suite, et le
  /// futur rendu par `cancel()` vit dans la zone racine (sous fake_async, il
  /// ne se résout jamais et bloquerait l'arrêt).
  static void _cancel(StreamSubscription<Object?>? subscription) {
    if (subscription != null) unawaited(subscription.cancel());
  }

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
          _traceSystemLevel(chunk.data);
          if (_liveDiarizationEnabled) {
            _liveDiarization?.sendAudio(chunk.data, chunk.timestampMs);
          }
        }
        _transcriptionRemoteDataSource.sendAudio(chunk);
      },
      onError: (Object error) {
        _log.error('Erreur capture audio stream: $error');
      },
    );
  }

  // Diagnostic : niveau du son du Mac (un flux muet ne produit aucun texte).
  int _systemChunks = 0;
  int _systemPeak = 0;

  void _traceSystemLevel(Uint8List pcm) {
    final ByteData bytes = ByteData.sublistView(pcm);
    for (int i = 0; i + 1 < pcm.length; i += 2) {
      final int v = bytes.getInt16(i, Endian.little).abs();
      if (v > _systemPeak) _systemPeak = v;
    }
    if (++_systemChunks % 200 == 1) {
      _log.info(
        'Son du Mac : $_systemChunks blocs reçus, crête '
        '${(_systemPeak / 32768 * 100).toStringAsFixed(1)} %',
      );
      _systemPeak = 0;
    }
  }

  Future<void> _flushRemoteTranscripts({
    required Duration limit,
    bool publish = false,
    Future<void>? skip,
  }) async {
    final Set<AudioSource> sourcesToFinalize =
        _transcriptionRemoteDataSource.activeSources;
    _stopFinalizationWaiters.clear();
    for (final AudioSource source in sourcesToFinalize) {
      _stopFinalizationWaiters[source] = Completer<void>();
    }
    _transcriptionRemoteDataSource.sendCommit(isFinal: true);
    if (_stopFinalizationWaiters.isEmpty) {
      if (publish) _finalisingRemaining.add(Duration.zero);
      return;
    }
    Duration last = _remainingAudio();
    void report() {
      final Duration now = _remainingAudio();
      if (now < last) last = now; // jamais croissant à l'écran
      _finalisingRemaining.add(last);
    }

    Timer? ticker;
    if (publish) {
      report();
      ticker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => report(),
      );
    }
    try {
      await Future.any<void>(<Future<void>>[
        Future.wait<void>(
          _stopFinalizationWaiters.values.map(
            (Completer<void> completer) => completer.future,
          ),
        ),
        ?skip,
      ]).timeout(limit);
    } on TimeoutException {
      _log.warning('Rattrapage non fini en $limit : le reste sera signalé');
    } finally {
      ticker?.cancel();
      _stopFinalizationWaiters.clear();
      if (publish) _finalisingRemaining.add(Duration.zero);
    }
  }

  Duration _remainingAudio() {
    final TranscriptionRemoteDataSource remote = _transcriptionRemoteDataSource;
    if (remote is! TranscriptionRemoteDataSourceImpl) return Duration.zero;
    return AudioSource.values.fold<Duration>(
      Duration.zero,
      (Duration sum, AudioSource s) => sum + remote.unacknowledgedAudio(s),
    );
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

  // Phrase en cours sauvée en base (sous son id final) au plus tard 2 s après
  // un nouveau mot ; l'écran garde son segment temporaire `current_*`.
  static const Duration _checkpointDelay = Duration(seconds: 2);
  final Map<AudioSource, String> _phraseId = <AudioSource, String>{};
  final Map<AudioSource, Timer> _checkpointTimers = <AudioSource, Timer>{};
  final Map<AudioSource, Future<void>> _provisionalWrites =
      <AudioSource, Future<void>>{};
  // Deux derniers textes finalisés par source (filtre des hallucinations).
  final Map<AudioSource, List<String>> _recentFinals =
      <AudioSource, List<String>>{
        AudioSource.input: <String>[],
        AudioSource.output: <String>[],
      };
  int _segmentSeq = 0;

  /// Id unique sans horloge : deux phrases finies dans la même milliseconde
  /// ne s'écrasent plus.
  String _newSegmentId(SessionEntity session, AudioSource source) =>
      '${session.id}_${source.name}_${++_segmentSeq}';

  /// Position dans la réunion d'un horodatage de capture (ms epoch).
  int _offsetOf(SessionEntity session, int epochMs) =>
      math.max(0, epochMs - session.createdAt.millisecondsSinceEpoch);

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
      // Micro dicté : rien à l'écran ni en base (le texte va à la dictée).
      if (source == AudioSource.input && _micDictated) return;

      // Une phrase renvoyée après coupure garde son id (et son début) : sa
      // retranscription remplace le provisoire déjà sauvé.
      if (!_phraseId.containsKey(source)) {
        _phraseStart[source] = _offsetOf(
          currentSession,
          clock.now().millisecondsSinceEpoch,
        );
        _phraseId[source] = _newSegmentId(currentSession, source);
      }
      _phrase[source]!.write(delta);

      _updateCurrentSegmentInUI(currentSession, source);
      _checkpointTimers[source] ??= Timer(
        _checkpointDelay,
        () => _checkpoint(currentSession, source),
      );
    } else if (event.type == utteranceResentEventType) {
      // Le serveur repart du début de la phrase : ses deltas réécrivent le
      // texte, sous le même id.
      _phrase[source] = StringBuffer();
    } else if (event.type == utteranceLostEventType) {
      _sealPhrase(currentSession, source);
    } else if (event.type == 'response.audio_transcript.done') {
      if (source == AudioSource.input && _routeToDictation(event)) {
        _releaseStopWaiter(source);
        return;
      }
      _trackFinalization(
        currentSession,
        source,
        event.text ?? _phrase[source]!.toString(),
        window: _transcriptionRemoteDataSource.windowOf(event),
      );
    }
  }

  /// Début de phrase perdu avec une socket : le texte déjà reçu ne sera pas
  /// retranscrit. Il devient sa propre ligne, telle quelle ; le `done`
  /// suivant ouvre une nouvelle phrase. Le repère de perte vient à part.
  void _sealPhrase(SessionEntity session, AudioSource source) {
    final String? id = _phraseId.remove(source);
    _checkpointTimers.remove(source)?.cancel();
    final Future<void>? provisionalWrite = _provisionalWrites.remove(source);
    final String text = TranscriptTextNormalizer.normalize(
      _phrase[source]!.toString(),
    );
    _phrase[source] = StringBuffer();
    _transcriptionService.segmentsStream.add(
      List<TranscriptSegmentEntity>.from(
        _transcriptionService.segmentsStream.value,
      )..removeWhere((TranscriptSegmentEntity s) => s.id == _tempId(source)),
    );
    if (id == null ||
        text.isEmpty ||
        TranscriptTextNormalizer.isForeignScript(text)) {
      return;
    }
    final TranscriptSegmentEntity segment = TranscriptSegmentEntity(
      id: id,
      sessionId: session.id,
      source: source,
      text: text,
      timestampMs: _phraseStart[source]!,
      createdAt: clock.now(),
    );
    late final Future<void> task;
    task = (provisionalWrite ?? Future<void>.value())
        .then((_) => _transcriptionService.saveSegment(segment))
        .then((_) => _sortAndDedupeSegments())
        .whenComplete(() => _pendingFinalizations.remove(task));
    _pendingFinalizations.add(task);
  }

  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Sauve en base la phrase en cours (provisoire, même id que la finale).
  void _checkpoint(SessionEntity session, AudioSource source) {
    _checkpointTimers.remove(source);
    final String? id = _phraseId[source];
    final String text = TranscriptTextNormalizer.normalize(
      _phrase[source]!.toString(),
    );
    // Sans lettre ni chiffre (« … » pendant le traitement), rien à garder.
    if (id == null ||
        !_wordChar.hasMatch(text) ||
        TranscriptTextNormalizer.isForeignScript(text)) {
      return;
    }
    final TranscriptSegmentEntity provisional = TranscriptSegmentEntity(
      id: id,
      sessionId: session.id,
      source: source,
      text: text,
      timestampMs: _phraseStart[source]!,
      createdAt: clock.now(),
    );
    // Écritures chaînées : un provisoire tardif n'écrase jamais la finale.
    _provisionalWrites[source] =
        (_provisionalWrites[source] ?? Future<void>.value()).then(
          (_) => _transcriptionService.saveProvisional(provisional),
        );
  }

  /// Finalise la phrase courante d'une source : remplace le segment temporaire
  /// (et le provisoire en base) par un segment définitif, ou l'écarte, et
  /// réinitialise le buffer.
  Future<void> _finalizeSegment(
    SessionEntity session,
    AudioSource source,
    String rawText, {
    UtteranceWindow? window,
  }) async {
    final List<TranscriptSegmentEntity> segs =
        List<TranscriptSegmentEntity>.from(
          _transcriptionService.segmentsStream.value,
        )..removeWhere((TranscriptSegmentEntity s) => s.id == _tempId(source));

    // Tout l'état de la phrase est lu avant le premier `await` : la phrase
    // suivante peut commencer pendant la sauvegarde.
    final String? provisionalId = _phraseId.remove(source);
    _checkpointTimers.remove(source)?.cancel();
    final Future<void>? provisionalWrite = _provisionalWrites.remove(source);
    final int phraseStart = window != null
        ? _offsetOf(session, window.startMs)
        : provisionalId != null
        ? _phraseStart[source]!
        : _offsetOf(session, clock.now().millisecondsSinceEpoch);
    _phrase[source] = StringBuffer();
    final String normalized = TranscriptTextNormalizer.normalize(rawText);
    final List<String> recent = _recentFinals[source]!;
    final List<String> previousTexts = List<String>.of(recent);
    recent.add(normalized);
    if (recent.length > 2) recent.removeAt(0);
    _transcriptionService.segmentsStream.add(segs);

    String? text;
    if (TranscriptTextNormalizer.isForeignScript(normalized)) {
      _log.info(
        'Phrase écartée (alphabet non latin, bruit probable): $normalized',
      );
    } else {
      text = TranscriptTextNormalizer.filterFinalText(
        normalized,
        // Sans fenêtre (fin décidée par le serveur), rien ne dit qu'il n'y
        // avait pas de parole.
        hadSpeechEnergy: window?.hadSpeech ?? true,
        previousTexts: previousTexts,
      );
      if (text == null && normalized.isNotEmpty) {
        _log.info('Phrase écartée (hallucination probable): $normalized');
      }
    }

    await provisionalWrite;
    if (text == null) {
      if (provisionalWrite != null && provisionalId != null) {
        await _transcriptionService.discardProvisional(provisionalId);
      }
    } else {
      final TranscriptSegmentEntity segment = TranscriptSegmentEntity(
        id: provisionalId ?? _newSegmentId(session, source),
        sessionId: session.id,
        source: source,
        text: text,
        timestampMs: phraseStart,
        createdAt: clock.now(),
      );
      await _transcriptionService.saveSegment(segment);
      if (source == AudioSource.output && _liveDiarizationEnabled) {
        _queueSpeakerLabel(
          segment.id,
          window ??
              // Phrase terminée par le serveur lui-même : intervalle estimé
              // depuis l'arrivée du premier mot (~1 s après le début réel).
              UtteranceWindow(
                startMs:
                    session.createdAt.millisecondsSinceEpoch +
                    phraseStart -
                    1000,
                endMs: clock.now().millisecondsSinceEpoch - 300,
              ),
        );
      }
    }
    _sortAndDedupeSegments();
  }

  /// Met a jour le segment temporaire (par source) en temps reel.
  void _updateCurrentSegmentInUI(SessionEntity session, AudioSource source) {
    final String text = TranscriptTextNormalizer.normalize(
      _phrase[source]!.toString(),
    );
    if (text.isEmpty || TranscriptTextNormalizer.isForeignScript(text)) return;

    final TranscriptSegmentEntity tempSegment = TranscriptSegmentEntity(
      id: _tempId(source),
      sessionId: session.id,
      source: source,
      text: text,
      timestampMs: _phraseStart[source]!,
      createdAt: clock.now(),
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
    String rawText, {
    UtteranceWindow? window,
  }) {
    late final Future<void> task;
    task = _finalizeSegment(session, source, rawText, window: window)
        .whenComplete(() {
          _pendingFinalizations.remove(task);
          // Plusieurs commits peuvent déjà être en vol si le modèle a pris du
          // retard. Ne couper les listeners qu'après le dernier `done` de la
          // source, sinon les fins de phrases suivantes seraient perdues.
          _releaseStopWaiter(source);
        });
    _pendingFinalizations.add(task);
    unawaited(task);
  }

  void _releaseStopWaiter(AudioSource source) {
    if (_transcriptionRemoteDataSource.activeSources.contains(source)) return;
    final Completer<void>? waiter = _stopFinalizationWaiters.remove(source);
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  // ---------------------------------------------------------------------------
  // Dictée pendant l'enregistrement (T2) : aucun flux en plus. Le texte du
  // micro transcrit entre l'appui et le relâchement va à la dictée, jamais à
  // la note ; attribution par fenêtre de parole de la phrase.
  // ---------------------------------------------------------------------------

  // Dictées de la session dont un `done` peut encore arriver (ou dont les
  // `done` tardifs doivent rester hors de la note).
  final List<MeetingDictation> _dictations = <MeetingDictation>[];

  MeetingDictation? get _openDictation {
    for (final MeetingDictation d in _dictations) {
      if (d._endEpochMs == null) return d;
    }
    return null;
  }

  bool get _micDictated =>
      _dictations.any((MeetingDictation d) => !d.isComplete);

  /// Commence une dictée sur le micro de la réunion en cours ; null hors
  /// réunion, en pause, ou si une dictée est déjà ouverte.
  MeetingDictation? beginDictation() {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (!_running || _capturePaused || session == null) return null;
    if (_openDictation != null) return null;
    final MeetingDictation d = MeetingDictation._(
      this,
      session,
      clock.now().millisecondsSinceEpoch,
    );
    _dictations.add(d);
    // Phrase à cheval sur l'appui : ce qui précède reste à la note.
    _transcriptionRemoteDataSource.sendCommit(
      isFinal: true,
      sources: <AudioSource>{AudioSource.input},
    );
    _clearMicPhrase();
    return d;
  }

  void _endDictation(MeetingDictation d, {required bool cancelled}) {
    if (d._endEpochMs != null) return;
    d._endEpochMs = clock.now().millisecondsSinceEpoch;
    if (cancelled) d.onText = null;
    final TranscriptionRemoteDataSource remote = _transcriptionRemoteDataSource;
    final Set<AudioSource> finalized = remote.sendCommit(
      isFinal: true,
      sources: <AudioSource>{AudioSource.input},
    );
    // Les `done` suivent l'ordre des commits : la dernière fenêtre en
    // attente, si elle est de la dictée, en est le dernier mot.
    if (remote is TranscriptionRemoteDataSourceImpl) {
      final UtteranceWindow? last = remote.lastPendingWindow(AudioSource.input);
      if (last != null && last.startMs >= d._startEpochMs) d._awaited = last;
    } else if (finalized.isNotEmpty) {
      d._awaitNext = true;
    }
    try {
      DictatedIntervalsStore(recordingsDir).add(
        d._session.id,
        DictatedInterval(
          startMs: _offsetOf(d._session, d._startEpochMs),
          endMs: _offsetOf(d._session, d._endEpochMs!),
        ),
      );
    } catch (e) {
      _log.warning('Intervalle dicté non noté: $e');
    }
    if (d._awaited == null && !d._awaitNext) {
      d._finish();
      return;
    }
    // Dernier `done` perdu (coupure : fenêtres en attente vidées) : la
    // dictée finit quand même, le micro revient à la note. Le texte tardif
    // de son intervalle reste hors de la note.
    d._giveUp = Timer(_dictationGiveUp, d._finish);
  }

  // Bien au-delà du délai de garde de la dictée (texte tardif encore livré).
  static const Duration _dictationGiveUp = Duration(seconds: 60);

  /// Un `done` micro de la dictée : il ne va pas à la note.
  bool _routeToDictation(TranscriptEventRemoteModel event) {
    final UtteranceWindow? window = _transcriptionRemoteDataSource.windowOf(
      event,
    );
    MeetingDictation? owner;
    for (final MeetingDictation d in _dictations) {
      final bool inRange = window != null
          ? window.startMs >= d._startEpochMs &&
                (d._endEpochMs == null || window.startMs < d._endEpochMs!)
          // Phrase close par le serveur seul : à la dictée qui tient le micro.
          : !d.isComplete;
      if (inRange) {
        owner = d;
        break;
      }
    }
    if (owner == null) return false;
    _clearMicPhrase();
    owner.onText?.call(event.text ?? '', window?.hadSpeech ?? true);
    if (identical(window, owner._awaited) || owner._awaitNext) owner._finish();
    return true;
  }

  /// Oublie la phrase micro en cours (texte de dictée, jamais à la note).
  void _clearMicPhrase() {
    const AudioSource source = AudioSource.input;
    _phraseId.remove(source);
    _checkpointTimers.remove(source)?.cancel();
    _phrase[source] = StringBuffer();
    _transcriptionService.segmentsStream.add(
      List<TranscriptSegmentEntity>.from(
        _transcriptionService.segmentsStream.value,
      )..removeWhere((TranscriptSegmentEntity s) => s.id == _tempId(source)),
    );
  }

  // ---------------------------------------------------------------------------
  // Interlocuteurs en direct
  // ---------------------------------------------------------------------------

  void _startLiveDiarization() {
    final LiveDiarizationService? diarization = _liveDiarization;
    if (diarization == null) return;
    _diarizationUpdates ??= diarization.updates.listen((_) => _resolveLabels());
    // Filet de sécurité : étiquette avec les trames disponibles les phrases
    // qui attendent depuis trop longtemps (serveur en retard).
    _labelTimer?.cancel();
    _labelTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _resolveLabels(),
    );
    unawaited(
      diarization.start().catchError((Object e) {
        _log.warning('Diarization en direct indisponible: $e');
      }),
    );
  }

  Future<void> _stopLiveDiarization() async {
    final LiveDiarizationService? diarization = _liveDiarization;
    _labelTimer?.cancel();
    _labelTimer = null;
    if (diarization == null || !_liveDiarizationEnabled) return;
    _liveDiarizationEnabled = false;
    await diarization.finish();
    _resolveLabels(force: true);
    _pendingLabels.clear();
    await diarization.stop();
  }

  void _queueSpeakerLabel(String segmentId, UtteranceWindow window) {
    _pendingLabels.add(_PendingLabel(segmentId, window, DateTime.now()));
    _resolveLabels();
  }

  /// Étiquette les phrases dont les trames de diarization sont arrivées.
  void _resolveLabels({bool force = false}) {
    final LiveDiarizationService? diarization = _liveDiarization;
    if (diarization == null || _pendingLabels.isEmpty) return;
    final DateTime now = DateTime.now();
    final Map<String, int> labels = Map<String, int>.of(_speakerLabels.value);
    bool changed = false;
    _pendingLabels.removeWhere((_PendingLabel p) {
      final ({bool covered, int? speaker}) r = diarization.resolve(
        p.window.startMs,
        p.window.endMs,
      );
      final bool expired = now.difference(p.queuedAt).inSeconds >= 20;
      if (!r.covered && !force && !expired) return false;
      if (r.speaker != null) {
        labels[p.segmentId] = r.speaker!;
        changed = true;
      }
      return true;
    });
    if (changed) _speakerLabels.add(labels);
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

/// Phrase système en attente de ses trames de diarization.
class _PendingLabel {
  _PendingLabel(this.segmentId, this.window, this.queuedAt);

  final String segmentId;
  final UtteranceWindow window;
  final DateTime queuedAt;
}

/// Dictée faite pendant un enregistrement, sur le micro de la réunion
/// ([LiveTranscriptionService.beginDictation]). Notée avec la session
/// (`<sessionId>_dictations.json`) à sa fin, annulée comprise.
final class MeetingDictation {
  MeetingDictation._(this._service, this._session, this._startEpochMs);

  final LiveTranscriptionService _service;
  final SessionEntity _session;
  final int _startEpochMs;
  int? _endEpochMs;
  UtteranceWindow? _awaited;
  bool _awaitNext = false;
  bool _complete = false;
  Timer? _giveUp;

  /// Texte brut de chaque phrase dictée, et si elle avait de la parole.
  void Function(String text, bool hadSpeech)? onText;

  /// Dernière phrase dictée reçue (ou aucune attendue).
  void Function()? onComplete;

  /// Toutes les phrases dictées sont arrivées.
  bool get isComplete => _complete;

  /// Relâchement : le micro revient à la note ; les phrases dictées encore
  /// attendues arrivent ensuite par [onText], puis [onComplete].
  void release() => _service._endDictation(this, cancelled: false);

  /// Annulation : ses mots sont jetés, ni sortie ni note.
  void cancel() => _service._endDictation(this, cancelled: true);

  void _finish() {
    if (_complete) return;
    _complete = true;
    _giveUp?.cancel();
    onComplete?.call();
  }
}
