import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart' as data;
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/transcription_health.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_diarization.service.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
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
    Future<int?> Function()? freeBytes,
  }) : _freeBytes = freeBytes,
       _gapBackfill = gapBackfill,
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
  // Place libre du volume des données ; null : pas de contrôle (tests).
  final Future<int?> Function()? _freeBytes;
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

  /// Début de la pause en cours, par piste : les WAV gardent leur place dans
  /// le temps (heure murale, comme les repères) en sautant la pause au
  /// premier chunk de la piste après la reprise (la capture met ~0,5 s à
  /// livrer, le système plus tard que le micro).
  DateTime? _micPausedAt;
  DateTime? _systemPausedAt;
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

  final PublishSubject<TranscriptSegmentEntity> _finalized =
      PublishSubject<TranscriptSegmentEntity>();

  /// Chaque phrase FINALE du direct (deux sources), une fois sauvée. Jamais
  /// un morceau provisoire, un repère de perte, une phrase écartée par les
  /// filtres ni le texte retrouvé après la réunion.
  // ponytail: une phrase scellée par une coupure de socket (`_sealPhrase`)
  // n'est pas émise : son début seul ferait une question à moitié dite.
  Stream<TranscriptSegmentEntity> get finalizedSegmentsStream =>
      _finalized.stream;

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
    SessionCalendarLink? calendarLink,
    TranscriptionEngine engine = TranscriptionEngine.local,
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
        // Moteur en ligne : l'adresse Mistral (la source distante y route
        // ses sockets) ; jamais le serveur local ni ses ports.
        webSocketUrl: engine == TranscriptionEngine.mistral
            ? MistralRealtimeClient.url
            : webSocketUrl ?? '${_ports.transcriptionWebSocket}',
        liveDiarization: liveDiarization,
        calendarLink: calendarLink,
        engine: engine,
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
    SessionCalendarLink? calendarLink,
    TranscriptionEngine engine = TranscriptionEngine.local,
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
      _micAudioEndMs = null;
      _serverCommand = serverCommand;
      _serverArgs = serverArgs;
      _resetServerSupervision();
      _keyRejected = false;
      // Moteur en ligne : pas de serveur local (ni démarrage ni
      // supervision) ; la source distante parle à Mistral.
      final bool local = engine == TranscriptionEngine.local;
      _supervising = local;

      // 1. Demarrer le serveur ML si pas deja en cours
      if (local) {
        final bool serverRunning = await _processManagerService
            .isServerRunning();
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
      }

      // 2. Connexion WebSocket (la source distante se reconnecte seule).
      _connectionSubscription = _transcriptionRemoteDataSource.connectionState
          .listen((domain.ConnectionState state) {
            _remoteState = state;
            _updateHealth();
          });
      _log.info('Connexion WebSocket: $webSocketUrl');
      try {
        await _transcriptionRemoteDataSource.connect(
          url: webSocketUrl,
          systemAudioEnabled: outputEnabled,
        );
      } on MistralKeyRejected {
        // Visible tout de suite ; pas de nouvelle tentative avec la même clé.
        _keyRejected = true;
        _updateHealth();
        rethrow;
      }
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
      await _transcriptionService.startSession(link: calendarLink);
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
          _watchRecorders();
        } catch (e) {
          _log.warning('Ouverture enregistreurs WAV échouée: $e');
          _micRecorder = null;
          _systemRecorder = null;
        }
      }
      // Place disque : avant le départ, puis toutes les 30 s.
      await _checkStorage();
      _storageTimer?.cancel();
      _storageTimer = Timer.periodic(
        RecordingStorage.checkEvery,
        (_) => unawaited(_checkStorage()),
      );

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
      _lossOfPhrase.clear();
      _gapMarkers.clear();
      _waitingMarkers.clear();
      _finalWindows.clear();
      _lastSealed.clear();
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
    _micPausedAt = _systemPausedAt = clock.now();
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

  /// Saute la pause d'une piste, jusqu'à l'arrivée de son premier chunk.
  Duration? _takePause(DateTime? since) =>
      since == null ? null : clock.now().difference(since);

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

    // Deconnecte le WebSocket AVANT de quitter l'écoute : un delta reçu entre
    // `input_audio.end` et `transcription.done` doit encore arriver.
    // L'audio encore en tampon de coupure est perdu pour la transcription :
    // la perte arrive par `audioGaps` et son repère doit être sauvé avant de
    // clore la session.
    await _transcriptionRemoteDataSource.disconnect();
    // ponytail: un tour de boucle suffit à livrer la perte (PublishSubject
    // asynchrone). Faire rendre les pertes par disconnect() si cela change.
    await Future<void>.delayed(Duration.zero);

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
    // Un disque encore plein à l'arrêt : l'intervalle ouvert est dit aussi.
    _noteMissingAudio();
    _storageTimer?.cancel();
    _storageTimer = null;
    for (final StreamSubscription<Object> sub in _wavErrorSubscriptions) {
      _cancel(sub);
    }
    _wavErrorSubscriptions.clear();
    _publishStorage(audioCopyFailing: false);
    _micRecorder = null;
    _systemRecorder = null;
    _capturePaused = false;
    _micPausedAt = _systemPausedAt = null;
    _captureInputDeviceId = null;
    _captureOutputEnabled = false;

    // Repli : phrases restantes si le serveur n'a pas répondu à temps. Après
    // la déconnexion, pour que la perte de l'arrêt soit connue et place la
    // phrase à l'heure de son audio (sonde 6 : 223,9 s, pas 410,8 s).
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
    final List<TranscriptSegmentEntity> segments = segmentsStream.value
        .where((TranscriptSegmentEntity s) => s.sessionId == sessionId)
        .toList();
    final List<DictatedInterval> dictated = DictatedIntervalsStore(
      recordingsDir,
    ).read(sessionId);
    final List<BackfillGap> plan = GapBackfillService.plan(
      segments,
      dictated: dictated,
    );
    // Un repère tout entier dans une dictée part aussi par le rattrapage
    // (sans serveur).
    if (plan.isEmpty &&
        GapBackfillService.dictatedMarkers(segments, dictated).isEmpty) {
      // Rien à rattraper ici, mais le serveur se libère : les sessions en
      // attente d'autres réunions repartent (en tâche de fond).
      if (retry != null && !_startRequested) {
        unawaited(retry.afterSession(sessionId));
      }
      return;
    }
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
        (Duration sum, BackfillGap g) =>
            sum + Duration(milliseconds: g.endMs - g.startMs),
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

  /// Repère de l'audio en souffrance, par source : UN enregistrement (un id,
  /// à l'écran et en base) tant que de l'audio de la source attend son
  /// `done` ou a été jeté. Son début est le plus ancien audio sans texte,
  /// jeté compris (sonde 10 : coupure plus longue que le tampon) ; les pertes
  /// déclarées qui le touchent s'y fondent (même id). Quand plus rien
  /// n'attend, il se réduit aux pertes déclarées, ou part.
  final Map<AudioSource, ({String id, int start, int end})> _waitingMarkers =
      <AudioSource, ({String id, int start, int end})>{};

  void _updateProvisionalMarkers() {
    final TranscriptionRemoteDataSource remote = _transcriptionRemoteDataSource;
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (remote is! TranscriptionRemoteDataSourceImpl || session == null) return;
    for (final AudioSource source in AudioSource.values) {
      final ({int startMs, int endMs})? range = remote.pendingRange(source);
      final bool waiting =
          range != null &&
          (remote.bufferedAudio(source) >= const Duration(seconds: 1) ||
              remote.hasDroppedAudio(source) ||
              (_draining &&
                  remote.unacknowledgedAudio(source) > Duration.zero));
      if (waiting) {
        _showWaiting(
          session,
          source,
          _offsetOf(session, range.startMs),
          _offsetOf(session, range.endMs),
        );
      } else {
        _endWaiting(session, source);
      }
    }
  }

  // Fenêtres (heures de réunion) des dernières phrases rendues, par source.
  final Map<AudioSource, List<(int, int)>> _finalWindows =
      <AudioSource, List<(int, int)>>{};

  /// Une perte qui commence dans l'audio d'une phrase dont le texte est
  /// rangé l'a coupée (sonde 10 : fin de la phrase 11 jetée, son début
  /// rendu) : le repère part du début de cette phrase, pour que le
  /// rattrapage la rende entière (et remplace la version coupée).
  int _cutStart(AudioSource source, int start) {
    int s = start;
    for (final (int from, int to) in _finalWindows[source] ?? <(int, int)>[]) {
      if (from < s && s < to) s = from;
    }
    return s;
  }

  void _noteFinalWindow(
    SessionEntity session,
    AudioSource source,
    int from,
    int to,
  ) {
    final List<(int, int)> windows = _finalWindows.putIfAbsent(
      source,
      () => <(int, int)>[],
    )..add((from, to));
    if (windows.length > 8) windows.removeAt(0);
    // Le texte arrive après la perte : le repère déjà là recule.
    for (final ({String id, int start, int end}) m
        in List<({String id, int start, int end})>.of(
          _gapMarkers[source] ?? const <({String id, int start, int end})>[],
        )) {
      if (from < m.start && m.start < to) {
        _writeGapMarker(session, source, from, m.start);
      }
    }
  }

  void _showWaiting(SessionEntity session, AudioSource source, int s, int e) {
    s = _cutStart(source, s);
    final ({String id, int start, int end})? current = _waitingMarkers[source];
    final List<({String id, int start, int end})> declared = _gapMarkers
        .putIfAbsent(source, () => <({String id, int start, int end})>[]);
    final List<({String id, int start, int end})> touched = declared
        .where(
          (({String id, int start, int end}) m) =>
              m.id == current?.id || (m.start <= e && s <= m.end),
        )
        .toList();
    final String id =
        current?.id ??
        (touched.isEmpty ? _newSegmentId(session, source) : touched.first.id);
    // Les pertes déclarées touchées n'en font plus qu'une, sous cet id.
    if (touched.isNotEmpty) {
      int from = touched.first.start;
      int to = touched.first.end;
      for (final ({String id, int start, int end}) m in touched) {
        from = math.min(from, m.start);
        to = math.max(to, m.end);
      }
      declared
        ..removeWhere(touched.contains)
        ..add((id: id, start: from, end: to));
      s = math.min(s, from);
      e = math.max(e, to);
    }
    if (current != null && current.start == s && current.end == e) return;
    _waitingMarkers[source] = (id: id, start: s, end: e);
    _showMarker(session, source, id, s, e, <String>[
      for (final ({String id, int start, int end}) m in touched)
        if (m.id != id) m.id,
    ]);
  }

  /// Plus rien n'attend pour [source] : le repère se réduit à ses pertes
  /// déclarées (même id), ou part.
  void _endWaiting(SessionEntity session, AudioSource source) {
    final ({String id, int start, int end})? current = _waitingMarkers.remove(
      source,
    );
    if (current == null) return;
    final ({String id, int start, int end})? declared = _gapMarkers[source]
        ?.where((({String id, int start, int end}) m) => m.id == current.id)
        .firstOrNull;
    if (declared != null) {
      if (declared.start != current.start || declared.end != current.end) {
        _showMarker(
          session,
          source,
          declared.id,
          declared.start,
          declared.end,
          const <String>[],
        );
      }
      return;
    }
    _chainWrite(current.id, () async {
      await _discard(current.id);
      _transcriptionService.segmentsStream.add(
        List<TranscriptSegmentEntity>.from(
          _transcriptionService.segmentsStream.value,
        )..removeWhere((TranscriptSegmentEntity x) => x.id == current.id),
      );
    });
  }

  Future<void> _clearProvisionalMarkers() async {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (session != null) {
      for (final AudioSource source in _waitingMarkers.keys.toList()) {
        _endWaiting(session, source);
      }
    }
    _waitingMarkers.clear();
    if (_pendingFinalizations.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.from(_pendingFinalizations));
    }
  }

  /// Libere les ressources du service.
  Future<void> dispose() async {
    _storageTimer?.cancel();
    _unsavedTimer?.cancel();
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
    await _finalized.close();
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

  // Moteur en ligne : la clé Mistral a été refusée.
  bool _keyRejected = false;

  void _updateHealth() {
    // `error` de la source distante : serveur muet malgré les reprises, la
    // perte est signalée ; l'enregistrement continue.
    final TranscriptionHealth next = _keyRejected
        ? TranscriptionHealth.keyRejected
        : _restartsExhausted || _remoteState == domain.ConnectionState.error
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

  static const String _untranscribedPrefix = 'Passage non transcrit';
  static final RegExp _untranscribed = RegExp(
    r'^Passage non transcrit \((\d+:\d{2}:\d{2}) – (\d+:\d{2}:\d{2})\)$',
  );

  /// Repère PERMANENT d'un passage dit que le modèle n'a pas su transcrire
  /// (écriture ou langue inattendue, sonde 5 : le retranscrire ne le répare
  /// pas). Jamais rattrapé ni remplacé ; affiché localisé
  /// (`transcription.gap.untranscribed`).
  static String untranscribedMarkerText(int startMs, int endMs) =>
      '$_untranscribedPrefix (${TranscriptFormatter.timestamp(startMs)} '
      '– ${TranscriptFormatter.timestamp(endMs)})';

  static const String _notRecordedAfterPrefix =
      "Rien n'a pu être enregistré après ";
  static const String _notRecordedAfterSuffix =
      ' (app arrêtée ou disque plein)';

  /// Repère OUVERT écrit au relancement après un arrêt brutal (app tuée,
  /// disque plein) : rien de la source n'a été gardé après [startMs], ni
  /// texte ni audio. Jamais rattrapé ni retiré, jamais pris pour du silence.
  static String notRecordedAfterMarkerText(int startMs) =>
      '$_notRecordedAfterPrefix${TranscriptFormatter.timestamp(startMs)}'
      '$_notRecordedAfterSuffix';

  static final RegExp _notRecordedAfter = RegExp(
    "^Rien n'a pu être enregistré après (\\d+:\\d{2}:\\d{2}) "
    r'\(app arrêtée ou disque plein\)$',
  );

  /// Vrai pour un texte écrit par [notRecordedAfterMarkerText].
  static bool isNotRecordedAfterMarker(String text) =>
      _notRecordedAfter.hasMatch(text);

  /// Heure (hh:mm:ss) d'un repère [notRecordedAfterMarkerText].
  static String? notRecordedAfterTime(String text) =>
      _notRecordedAfter.firstMatch(text)?.group(1);

  static const String _noAudioCopyPrefix = 'Pas de copie audio';

  /// Repère d'un intervalle dont l'audio n'a pas pu être gardé (disque
  /// plein) : ni rattrapable, ni du silence vérifié.
  static String noAudioCopyMarkerText(int startMs, int endMs) =>
      '$_noAudioCopyPrefix : ${TranscriptFormatter.timestamp(startMs)} '
      '– ${TranscriptFormatter.timestamp(endMs)}';

  /// Vrai pour un texte écrit par [noAudioCopyMarkerText].
  static bool isNoAudioCopyMarker(String text) =>
      text.startsWith('$_noAudioCopyPrefix : ');

  /// Vrai pour un texte écrit par [untranscribedMarkerText].
  static bool isUntranscribedMarker(String text) =>
      _untranscribed.hasMatch(text);

  /// Heures (hh:mm:ss) de début et de fin d'un passage non transcrit.
  static (String, String)? untranscribedTimes(String text) {
    final RegExpMatch? m = _untranscribed.firstMatch(text);
    return m == null ? null : (m.group(1)!, m.group(2)!);
  }

  void _onAudioGap(AudioGap gap) {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (session == null) return;
    final int startMs = _offsetOf(session, gap.startMs);
    // La phrase en cours de cette source est emportée par la perte : son
    // audio commence au début de la perte.
    if (_phraseId.containsKey(gap.source)) {
      _lossOfPhrase[gap.source] = startMs;
    } else if (_lastSealed.remove(gap.source)
        case final TranscriptSegmentEntity sealed
        when startMs < sealed.timestampMs) {
      _savePartial(sealed.copyWith(timestampMs: startMs));
    }
    _writeGapMarker(
      session,
      gap.source,
      startMs,
      _offsetOf(session, gap.endMs),
    );
  }

  // Repères de perte écrits dans cette session, par source, dans l'ordre :
  // (id, début, fin) en heures de réunion.
  final Map<AudioSource, List<({String id, int start, int end})>> _gapMarkers =
      <AudioSource, List<({String id, int start, int end})>>{};

  /// Seul endroit qui écrit un repère de perte. Les repères d'une source ne
  /// se chevauchent jamais (sonde 7 : trois repères emboîtés) : une perte
  /// qui touche ou recoupe des repères de la même source les fusionne en un
  /// seul, l'union, sous l'id du premier ; les autres sont retirés.
  void _writeGapMarker(
    SessionEntity session,
    AudioSource source,
    int start,
    int end,
  ) {
    start = _cutStart(source, start);
    final List<({String id, int start, int end})> markers = _gapMarkers
        .putIfAbsent(source, () => <({String id, int start, int end})>[]);
    // L'audio en souffrance qui recoupe la perte porte déjà un repère : la
    // perte s'y fond, sous son id, avec les pertes déjà déclarées sous cet
    // id (sonde 11 : sinon deux entrées du même id, et le repère se
    // réduisait à la première, sous l'audio jamais rendu).
    final ({String id, int start, int end})? waiting = _waitingMarkers[source];
    final bool intoWaiting =
        waiting != null && waiting.start <= end && start <= waiting.end;
    final List<({String id, int start, int end})> touched = markers
        .where(
          (({String id, int start, int end}) m) =>
              (m.start <= end && start <= m.end) ||
              (intoWaiting && m.id == waiting.id),
        )
        .toList();
    int from = start;
    int to = end;
    for (final ({String id, int start, int end}) m in touched) {
      if (m.start < from) from = m.start;
      if (m.end > to) to = m.end;
    }
    final String id = intoWaiting
        ? waiting.id
        : touched.isEmpty
        ? _newSegmentId(session, source)
        : touched.first.id;
    final List<String> absorbed = <String>[
      for (final ({String id, int start, int end}) m in touched)
        if (m.id != id) m.id,
    ];
    markers
      ..removeWhere(touched.contains)
      ..add((id: id, start: from, end: to));
    int shownFrom = from;
    int shownTo = to;
    if (intoWaiting) {
      shownFrom = math.min(from, waiting.start);
      shownTo = math.max(to, waiting.end);
      _waitingMarkers[source] = (id: id, start: shownFrom, end: shownTo);
    }
    _log.warning(
      'Audio non transcrit: ${gapMarkerText(from, to)} (${source.name})',
    );
    _showMarker(session, source, id, shownFrom, shownTo, absorbed);
  }

  /// Seule écriture d'un repère de perte : rangé (réessayé), puis à l'écran
  /// en une émission qui remplace les repères absorbés, retirés ensuite.
  void _showMarker(
    SessionEntity session,
    AudioSource source,
    String id,
    int from,
    int to,
    List<String> absorbed,
  ) {
    final TranscriptSegmentEntity marker = TranscriptSegmentEntity(
      id: id,
      sessionId: session.id,
      source: source,
      text: gapMarkerText(from, to),
      timestampMs: from,
      createdAt: clock.now(),
    );
    // Atomique pour l'utilisateur : l'union est rangée d'abord (réessayée si
    // l'écriture échoue), les repères absorbés ne partent qu'ensuite ; aucun
    // intervalle ne reste sans repère.
    final List<Future<void>> absorbedWrites = <Future<void>>[
      for (final String other in absorbed) ?_segmentWrites[other],
    ];
    _chainWrite(id, () async {
      await Future.wait(absorbedWrites);
      // Une seule émission : l'union remplace les absorbés à l'écran, rangée
      // ou non (montrée même si la base refuse).
      if (session.id == currentSessionStream.valueOrNull?.id) {
        _transcriptionService.segmentsStream.add(
          List<TranscriptSegmentEntity>.from(
              _transcriptionService.segmentsStream.value,
            )
            ..removeWhere(
              (TranscriptSegmentEntity x) =>
                  x.id == id || absorbed.contains(x.id),
            )
            ..add(marker),
        );
        _sortAndDedupeSegments();
      }
      // Rangée d'abord (réessayée sans limite), les absorbés ne partent
      // qu'ensuite.
      await _persist(
        marker,
        show: false,
        then: () async {
          for (final String other in absorbed) {
            await _discard(other);
          }
        },
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Place disque (règles : [RecordingStorage]) et copie audio (WAV).
  // ---------------------------------------------------------------------------

  final BehaviorSubject<RecordingStorage> _storage =
      BehaviorSubject<RecordingStorage>.seeded(const RecordingStorage());
  Timer? _storageTimer;
  final List<StreamSubscription<Object>> _wavErrorSubscriptions =
      <StreamSubscription<Object>>[];
  // Intervalles sans copie déjà dits dans la note, par enregistreur.
  final Map<WavRecorder, int> _missingNoted = <WavRecorder, int>{};

  /// Place disque de la note en cours (valeur courante + changements).
  Stream<RecordingStorage> get storageStream => _storage.stream;

  void _publishStorage({bool? audioCopyFailing}) {
    if (_storage.isClosed) return;
    final RecordingStorage next = _storage.value.copyWith(
      unsavedLines: _unsaved.length,
      audioCopyFailing: audioCopyFailing,
    );
    if (next != _storage.value) _storage.add(next);
  }

  Future<void> _checkStorage() async {
    final Future<int?> Function()? probe = _freeBytes;
    if (probe == null || _storage.isClosed) return;
    final int? free = await probe();
    if (_storage.isClosed) return;
    final RecordingStorage next = _storage.value.withFreeBytes(
      free,
      _captureOutputEnabled ? 2 : 1,
    );
    if (next != _storage.value) _storage.add(next);
  }

  void _watchRecorders() {
    for (final WavRecorder? w in <WavRecorder?>[
      _micRecorder,
      _systemRecorder,
    ]) {
      if (w == null) continue;
      _missingNoted[w] = 0;
      _wavErrorSubscriptions.add(
        w.writeErrors.listen((Object e) {
          _log.error('Copie audio (WAV) en échec', e);
          _publishStorage(audioCopyFailing: true);
        }),
      );
    }
  }

  /// Après une écriture WAV : l'écriture a pu reprendre (intervalle sans
  /// copie dit dans la note).
  void _afterWavWrite() {
    final bool failing =
        (_micRecorder?.failing ?? false) || (_systemRecorder?.failing ?? false);
    if (failing != _storage.value.audioCopyFailing) {
      _publishStorage(audioCopyFailing: failing);
    }
    _noteMissingAudio();
  }

  /// Écrit dans la note un repère « pas de copie audio » pour chaque
  /// intervalle neuf que les WAV n'ont pas pu garder : le rattrapage ne le
  /// couvrira pas, et ce n'est pas du silence.
  void _noteMissingAudio() {
    final SessionEntity? session = currentSessionStream.valueOrNull;
    if (session == null) return;
    for (final (WavRecorder? w, AudioSource source)
        in <(WavRecorder?, AudioSource)>[
          (_micRecorder, AudioSource.input),
          (_systemRecorder, AudioSource.output),
        ]) {
      if (w == null) continue;
      final List<({int startMs, int endMs})> missing = w.missing;
      final int done = _missingNoted[w] ?? 0;
      for (final ({int startMs, int endMs}) m in missing.skip(done)) {
        final TranscriptSegmentEntity marker = TranscriptSegmentEntity(
          id: _newSegmentId(session, source),
          sessionId: session.id,
          source: source,
          text: noAudioCopyMarkerText(m.startMs, m.endMs),
          timestampMs: m.startMs,
          createdAt: clock.now(),
        );
        _log.warning('Pas de copie audio: ${marker.text} (${source.name})');
        _chainWrite(marker.id, () async {
          await _persist(marker);
          _sortAndDedupeSegments();
        });
      }
      _missingNoted[w] = missing.length;
    }
  }

  // ---------------------------------------------------------------------------
  // Rangement sans perte : une ligne (phrase ou repère) que la base refuse
  // (disque plein, SQLite) reste montrée, gardée ici et réessayée sans limite
  // tant que l'app vit, même après l'arrêt ; l'utilisateur voit le nombre de
  // lignes en attente ([RecordingStorage.unsavedLines]).
  // ponytail: en mémoire seulement ; un arrêt brutal pendant que la base
  // refuse perd ces lignes (fichier de secours si cela arrive).
  // ---------------------------------------------------------------------------

  final Map<
    String,
    ({
      TranscriptSegmentEntity segment,
      bool show,
      Future<void> Function()? then,
    })
  >
  _unsaved =
      <
        String,
        ({
          TranscriptSegmentEntity segment,
          bool show,
          Future<void> Function()? then,
        })
      >{};
  Timer? _unsavedTimer;
  int _unsavedRound = 0;
  static const Duration _maxUnsavedWait = Duration(seconds: 30);

  /// Range [segment] (la dernière valeur voulue pour son id) ; si [show], le
  /// montre aussi, rangé ou non, tant que sa séance est à l'écran. [then]
  /// suit le rangement réussi.
  Future<bool> _persist(
    TranscriptSegmentEntity segment, {
    bool show = true,
    Future<void> Function()? then,
  }) async {
    bool ok;
    try {
      ok = await _transcriptionService.saveProvisional(segment);
      // Une base fermée lève une Error (StateError), pas une Exception :
      // réessayée comme les autres refus.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      _log.error('Ligne non rangée', e);
      ok = false;
    }
    if (show && segment.sessionId == currentSessionStream.valueOrNull?.id) {
      _transcriptionService.segmentsStream.add(
        List<TranscriptSegmentEntity>.from(
            _transcriptionService.segmentsStream.value,
          )
          ..removeWhere((TranscriptSegmentEntity x) => x.id == segment.id)
          ..add(segment),
      );
    }
    if (ok) {
      final bool waited = _unsaved.remove(segment.id) != null;
      if (then != null) await then();
      if (waited) _publishStorage();
      return true;
    }
    _unsaved[segment.id] = (segment: segment, show: show, then: then);
    _publishStorage();
    _armUnsavedRetry();
    return false;
  }

  /// Retire [id] de la base, et de l'attente : un repère absorbé ou retiré
  /// ne revient jamais.
  Future<void> _discard(String id) async {
    if (_unsaved.remove(id) != null) _publishStorage();
    await _transcriptionService.discardProvisional(id);
  }

  void _armUnsavedRetry() {
    if (_unsavedTimer != null || _unsaved.isEmpty) return;
    final int seconds = 1 << math.min(_unsavedRound, 5);
    final Duration wait = Duration(seconds: seconds) > _maxUnsavedWait
        ? _maxUnsavedWait
        : Duration(seconds: seconds);
    _unsavedRound++;
    _unsavedTimer = Timer(wait, () {
      _unsavedTimer = null;
      for (final MapEntry<
            String,
            ({
              TranscriptSegmentEntity segment,
              bool show,
              Future<void> Function()? then,
            })
          >
          e
          in _unsaved.entries.toList()) {
        _chainWrite(e.key, () async {
          // Une écriture plus récente a pu le ranger entre-temps.
          final ({
            TranscriptSegmentEntity segment,
            bool show,
            Future<void> Function()? then,
          })?
          now = _unsaved[e.key];
          if (now == null) return;
          await _persist(now.segment, show: now.show, then: now.then);
          if (_unsaved.isEmpty) _unsavedRound = 0;
        });
      }
    });
  }

  // Écritures chaînées par id de segment : la dernière valeur voulue est
  // toujours écrite en dernier (revue : un re-rangement non chaîné pouvait
  // être écrasé par la première écriture, plus lente).
  final Map<String, Future<void>> _segmentWrites = <String, Future<void>>{};

  void _chainWrite(String id, Future<void> Function() write) {
    late final Future<void> task;
    // Une écriture ratée plus tôt pour cet id n'empêche pas la suivante.
    task = (_segmentWrites[id] ?? Future<void>.value())
        .catchError((Object e) => _log.error('Écriture de $id ratée', e))
        .then((_) => write())
        .catchError((Object e) => _log.error('Écriture de $id ratée', e))
        .whenComplete(() {
          _pendingFinalizations.remove(task);
          if (identical(_segmentWrites[id], task)) _segmentWrites.remove(id);
        });
    _segmentWrites[id] = task;
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
          final Duration? gap = _takePause(_micPausedAt);
          if (gap != null) _micRecorder?.skip(gap);
          _micPausedAt = null;
          _micRecorder?.append(chunk.data).then((_) => _afterWavWrite());
          _micAudioEndMs = chunk.timestampMs + chunk.data.length ~/ 32;
        } else {
          final Duration? gap = _takePause(_systemPausedAt);
          if (gap != null) _systemRecorder?.skip(gap);
          _systemPausedAt = null;
          _systemRecorder?.append(chunk.data).then((_) => _afterWavWrite());
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
    // Clé refusée : rien ne reviendra d'une socket refusée, pas d'attente
    // (le repère de perte reste).
    if (_stopFinalizationWaiters.isEmpty || _keyRejected) {
      _stopFinalizationWaiters.clear();
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
    if (event.type == keyRejectedEventType) {
      // Refus en pleine réunion : visible tout de suite ; le WAV continue,
      // la perte est sous un repère à l'arrêt.
      _keyRejected = true;
      _updateHealth();
      return;
    }
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
        _lossOfPhrase.remove(source);
        _lastSealed.remove(source);
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
      timestampMs: _currentPhraseStart(source),
      createdAt: clock.now(),
    );
    _lossOfPhrase.remove(source);
    // La perte qui l'emporte peut arriver juste après (autre flux) : elle
    // replacera alors cette phrase à l'heure de son audio.
    _lastSealed[source] = segment;
    _savePartial(segment, after: provisionalWrite);
  }

  /// Dernière phrase scellée de chaque source, tant qu'aucune autre phrase
  /// n'a commencé : la perte déclarée ensuite la replace à son début.
  final Map<AudioSource, TranscriptSegmentEntity> _lastSealed =
      <AudioSource, TranscriptSegmentEntity>{};

  void _savePartial(TranscriptSegmentEntity segment, {Future<void>? after}) {
    _chainWrite(segment.id, () async {
      await after;
      await _persist(segment);
      _sortAndDedupeSegments();
    });
  }

  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  // Début (heure de réunion) de la perte déclarée pendant que la phrase en
  // cours de chaque source était dite : c'est là que son AUDIO commence,
  // pas à l'arrivée de son premier delta (sonde 6 : sous retard, minutes
  // plus tard). La perte d'une source part de son plus vieil audio sans
  // `done`, celui de la phrase en cours.
  final Map<AudioSource, int> _lossOfPhrase = <AudioSource, int>{};

  /// Heure de la phrase en cours de [source] : celle de son premier delta,
  /// ou plus tôt le début de la perte qui l'a emportée.
  int _currentPhraseStart(AudioSource source) {
    final int fromDelta = _phraseStart[source]!;
    final int? loss = _lossOfPhrase[source];
    return loss != null && loss < fromDelta ? loss : fromDelta;
  }

  static final RegExp _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static int _wordCount(String text) => _wordRun.allMatches(text).length;

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
      timestampMs: _currentPhraseStart(source),
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
    // Phrase coupée par l'arrêt : un texte final plus court que ce qui a
    // déjà été dit n'efface pas la phrase plus complète (sonde 6).
    final String said = TranscriptTextNormalizer.normalize(
      _phrase[source]!.toString(),
    );
    final String finalText = _draining && _wordCount(said) > _wordCount(rawText)
        ? said
        : rawText;
    final int phraseStart = window != null
        ? _offsetOf(session, window.startMs)
        : provisionalId != null
        ? _currentPhraseStart(source)
        : _offsetOf(session, clock.now().millisecondsSinceEpoch);
    _lossOfPhrase.remove(source);
    _phrase[source] = StringBuffer();
    final String normalized = TranscriptTextNormalizer.normalize(finalText);
    final List<String> recent = _recentFinals[source]!;
    final List<String> previousTexts = List<String>.of(recent);
    recent.add(normalized);
    if (recent.length > 2) recent.removeAt(0);
    _transcriptionService.segmentsStream.add(segs);

    String? text;
    // Écriture non latine ou langue non attendue : avec de la parole, ce
    // n'est pas du bruit mais une phrase que le modèle rate (sonde 5 : de
    // façon déterministe, la retranscrire ne la répare pas). Elle devient un
    // passage non transcrit, signalé et permanent. Sans parole, écartée.
    // ponytail: le pseudo-espagnol de la sonde 5 n'est pas détecté par les
    // listes de mots-outils ; limite connue.
    final bool wrongOutput =
        TranscriptTextNormalizer.isForeignScript(normalized) ||
        TranscriptTextNormalizer.isUnexpectedLanguage(normalized);
    final bool untranscribed = wrongOutput && window?.hadSpeech == true;
    if (wrongOutput) {
      _log.info(
        'Phrase mal transcrite (écriture ou langue): $normalized'
        '${untranscribed ? ', passage non transcrit' : ', écartée'}',
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
    if (untranscribed) {
      final int start = _offsetOf(session, window!.startMs);
      await _persist(
        TranscriptSegmentEntity(
          id: provisionalId ?? _newSegmentId(session, source),
          sessionId: session.id,
          source: source,
          text: untranscribedMarkerText(
            start,
            _offsetOf(session, window.endMs),
          ),
          timestampMs: start,
          createdAt: clock.now(),
        ),
      );
    } else if (text == null) {
      if (provisionalWrite != null && provisionalId != null) {
        await _discard(provisionalId);
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
      await _persist(segment);
      if (!_finalized.isClosed) _finalized.add(segment);
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
      timestampMs: _currentPhraseStart(source),
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
    if (window != null) {
      _noteFinalWindow(
        session,
        source,
        _offsetOf(session, window.startMs),
        _offsetOf(session, window.endMs),
      );
    }
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

  // Fin du dernier audio micro relayé, à l'horloge de la capture (celle des
  // fenêtres de parole) : bornes de la dictée comparables aux phrases, même
  // si la capture a du retard sur l'horloge murale.
  int? _micAudioEndMs;

  int _micAudioBoundary() =>
      _micAudioEndMs ?? clock.now().millisecondsSinceEpoch;

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
      _micAudioBoundary(),
    );
    _dictations.add(d);
    // Phrase à cheval sur l'appui : ce qui précède reste à la note.
    _transcriptionRemoteDataSource.sendCommit(
      isFinal: true,
      sources: <AudioSource>{AudioSource.input},
    );
    // La phrase de réunion en cours garde son id : son `done` remplace le
    // provisoire déjà sauvé (sinon deux lignes dans la note).
    return d;
  }

  void _endDictation(MeetingDictation d, {required bool cancelled}) {
    if (d._endEpochMs != null) return;
    d._endEpochMs = math.max(d._startEpochMs, _micAudioBoundary());
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

  void _abandonDictation(MeetingDictation d) {
    d
      ..onText = null
      ..onComplete = null;
    _dictations.remove(d);
    d._finish();
  }

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

  /// Appui abandonné (raccourci d'une autre app) : ce n'était pas une
  /// dictée. Aucun intervalle noté, le micro dit depuis l'appui va à la note.
  void abandon() => _service._abandonDictation(this);

  void _finish() {
    if (_complete) return;
    _complete = true;
    _giveUp?.cancel();
    onComplete?.call();
  }
}
