import 'dart:async';

import 'package:clock/clock.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:rxdart/rxdart.dart';

/// État visible de la dictée.
sealed class DictationState {
  const DictationState();
}

/// Rien en cours.
final class DictationIdle extends DictationState {
  const DictationIdle();
}

/// Appui reçu, serveur pas encore disponible : l'audio est gardé (borné).
final class DictationStarting extends DictationState {
  const DictationStarting();
}

/// Écoute : la parole part au serveur.
final class DictationListening extends DictationState {
  const DictationListening();
}

/// Capture finie, texte final attendu.
final class DictationTranscribing extends DictationState {
  const DictationTranscribing();
}

/// Texte produit.
final class DictationDone extends DictationState {
  const DictationDone(this.text, this.delivery);

  final String text;
  final DictationDelivery delivery;
}

/// Rien de dit (silence, ou phrase sans parole).
final class DictationNothingHeard extends DictationState {
  const DictationNothingHeard();
}

/// Échec explicite.
final class DictationError extends DictationState {
  const DictationError(this.reason);

  final DictationErrorReason reason;
}

/// Comment le texte a été produit.
enum DictationDelivery {
  /// Mode presse-papiers.
  clipboard,

  /// Collé dans l'app au premier plan (presse-papiers d'avant restauré).
  pasted,

  /// Collage demandé, Accessibilité absente : laissé au presse-papiers.
  clipboardNoAccessibility,

  /// ⌘V refusé : laissé au presse-papiers.
  clipboardPasteFailed,

  /// Arrivé après le délai de garde : presse-papiers, jamais collé.
  clipboardLate,
}

/// Cause d'une [DictationError].
enum DictationErrorReason { timeout, microphone, serverUnavailable }

/// État du raccourci global.
enum ShortcutStatus { disabled, registered, unavailable }

/// Dictée (T2) : raccourci global maintenu (ou appui bref = bascule), texte
/// final produit une seule fois (presse-papiers ou collage).
///
/// Hors réunion : un flux à elle, micro seul, sur le serveur partagé.
/// Pendant un enregistrement : aucun flux en plus, le texte du micro de la
/// réunion entre l'appui et le relâchement ([MeetingDictation]).
/// Le serveur est séquentiel : la dictée se déclare à l'arbitre de l'appui à
/// sa fin.
final class DictationController {
  /// Cree une instance de [DictationController].
  DictationController({
    required TranscriptionServerArbiter arbiter,
    required GlobalShortcutChannel shortcuts,
    required TextOutputChannel textOutput,
    required AudioCaptureChannel audioCapture,
    required TranscriptionRemoteDataSource transcription,
    required ProcessManagerService processManager,
    required LiveTranscriptionService liveTranscription,
    required String serverCommand,
    required List<String> serverArgs,
    required String webSocketUrl,
  }) : _arbiter = arbiter,
       _shortcuts = shortcuts,
       _output = textOutput,
       _audio = audioCapture,
       _remote = transcription,
       _processes = processManager,
       _live = liveTranscription,
       _serverCommand = serverCommand,
       _serverArgs = serverArgs,
       _webSocketUrl = webSocketUrl {
    _serverStates = _processes.stateStream.listen((ServerState state) {
      if (state == ServerState.ready) _serverReady = true;
      if (state == ServerState.stopped || state == ServerState.error) {
        _serverReady = false;
      }
    });
    _live.recordingHandover = _handOverToRecording;
  }

  /// En deçà, un appui est bref : la dictée continue après le relâchement
  /// (bascule), un second appui l'arrête.
  static const Duration holdThreshold = Duration(milliseconds: 300);

  /// Texte final attendu au plus tard ce délai après la fin de la capture.
  static const Duration finalTextTimeout = Duration(seconds: 15);

  /// Démarrage du serveur attendu au plus tard (démarrage à froid ~10 s).
  static const Duration serverStartTimeout = Duration(seconds: 30);

  /// Audio gardé au plus en attendant le serveur ; au-delà la capture
  /// s'arrête et tout est transcrit une fois le serveur prêt.
  static const Duration maxStartingBuffer = Duration(seconds: 20);

  /// Attente après ⌘V avant de remettre le presse-papiers d'avant : l'appel
  /// Swift rend la main avant que l'app cible ait collé.
  static const Duration pasteRestoreDelay = Duration(milliseconds: 500);

  static const String _readyPattern = 'VOXMLX_READY';
  static const int _chunkMs = 100;

  final TranscriptionServerArbiter _arbiter;
  final GlobalShortcutChannel _shortcuts;
  final TextOutputChannel _output;
  final AudioCaptureChannel _audio;
  final TranscriptionRemoteDataSource _remote;
  final ProcessManagerService _processes;
  final LiveTranscriptionService _live;
  final String _serverCommand;
  final List<String> _serverArgs;
  final String _webSocketUrl;
  final Log _log = Log.named('DictationController');

  // Écoutés après le premier enregistrement réussi : sans plugin (tests),
  // rien n'écoute le canal d'événements.
  StreamSubscription<ShortcutEvent>? _shortcutEvents;
  late final StreamSubscription<ServerState> _serverStates;
  final BehaviorSubject<DictationState> _state =
      BehaviorSubject<DictationState>.seeded(const DictationIdle());
  final BehaviorSubject<ShortcutStatus> _shortcutStatus =
      BehaviorSubject<ShortcutStatus>.seeded(ShortcutStatus.disabled);

  DictationSettings? _settings;
  bool _serverReady = false;
  Future<void>? _serverStart;
  Future<void>? _lending;
  _Run? _run;

  /// État courant.
  DictationState get state => _state.value;

  /// États successifs.
  Stream<DictationState> get stateStream => _state.stream;

  /// État du raccourci global.
  ShortcutStatus get shortcutStatus => _shortcutStatus.value;

  /// États successifs du raccourci global.
  Stream<ShortcutStatus> get shortcutStatusStream => _shortcutStatus.stream;

  bool get _enabled => _settings?.enabled ?? false;

  /// Applique [settings] : raccourci (ré)enregistré ou libéré ; dictée
  /// activée, serveur démarré tout de suite sans l'attendre.
  Future<void> apply(DictationSettings settings) async {
    final DictationSettings? previous = _settings;
    _settings = settings;
    final bool wasEnabled = previous?.enabled ?? false;
    if (!settings.enabled) {
      if (_run case final _Run run when !run.finished) _cancel(run);
      if (wasEnabled) await _shortcuts.unregister();
      _shortcutStatus.add(ShortcutStatus.disabled);
      return;
    }
    final bool sameShortcut =
        wasEnabled &&
        previous!.shortcut.keyCode == settings.shortcut.keyCode &&
        previous.shortcut.modifiers == settings.shortcut.modifiers;
    if (!sameShortcut) {
      if (wasEnabled) await _shortcuts.unregister();
      final bool ok = await _shortcuts.register(
        keyCode: settings.shortcut.keyCode,
        modifiers: settings.shortcut.modifiers,
      );
      if (ok) _shortcutEvents ??= _shortcuts.events.listen(_onShortcut);
      _shortcutStatus.add(
        ok ? ShortcutStatus.registered : ShortcutStatus.unavailable,
      );
    }
    unawaited(_warmServer());
  }

  /// Prête le serveur à [work] (coach, diarization : un seul modèle à la
  /// fois en mémoire) : arrêté pendant le travail, relancé dès la fin si la
  /// dictée est activée. Rend le résultat ou l'erreur de [work].
  Future<T> lendServer<T>(Future<T> Function() work) async {
    // Une dictée hors réunion en cours finit d'abord (son flux est sur ce
    // serveur), au plus le temps d'un démarrage et d'un texte final.
    final _Run? running = _run;
    if (running != null && !running.finished && running.meeting == null) {
      await running.ended.future.timeout(
        serverStartTimeout + finalTextTimeout,
        onTimeout: () {},
      );
    }
    final Completer<void> lent = Completer<void>();
    _lending = lent.future;
    _serverReady = false;
    try {
      try {
        await _processes.stopServer();
      } catch (e) {
        _log.warning('Arrêt du serveur avant le travail prêté: $e');
      }
      return await work();
    } finally {
      _lending = null;
      // Mêmes gardes qu'au lancement : jamais par-dessus une réunion qui a
      // démarré son serveur entre-temps (un 2e démarrage tue le 1er).
      if (_enabled) unawaited(_warmServer());
      lent.complete();
    }
  }

  /// Libère le raccourci et les flux.
  Future<void> dispose() async {
    if (_run case final _Run run when !run.finished) _cancel(run);
    _live.recordingHandover = null;
    await _shortcutEvents?.cancel();
    await _serverStates.cancel();
    await _state.close();
    await _shortcutStatus.close();
  }

  // ---------------------------------------------------------------------------
  // Serveur
  // ---------------------------------------------------------------------------

  Future<void> _warmServer() async {
    if (_lending != null || _live.isRecording) return;
    try {
      if (await _processes.isServerRunning()) {
        _serverReady = true;
        return;
      }
      await _startServerOnce();
    } catch (e) {
      _log.warning('Démarrage du serveur pour la dictée: $e');
    }
  }

  // Un seul démarrage en vol : pas de 2e démarrage à froid.
  Future<void> _startServerOnce() => _serverStart ??= () async {
    try {
      await _processes.startServer(
        command: _serverCommand,
        args: _serverArgs,
        readyPattern: _readyPattern,
      );
      _serverReady = true;
    } finally {
      _serverStart = null;
    }
  }();

  /// Vrai une fois le serveur libre et prêt pour le flux de [run].
  Future<bool> _awaitServer(_Run run) async {
    DateTime? deadline;
    while (!run.finished) {
      final Future<void>? lending = _lending;
      if (lending != null) {
        await lending; // le délai ne court pas pendant l'emprunt
        continue;
      }
      if (_live.isRunning) return false; // une réunion a pris le micro
      if (_live.isRecording) {
        await _live.whenIdle(); // vidange d'une réunion arrêtée
        continue;
      }
      if (_serverReady) return true;
      deadline ??= clock.now().add(serverStartTimeout);
      final Duration left = deadline.difference(clock.now());
      try {
        await _startServerOnce().timeout(
          left.isNegative ? Duration.zero : left,
        );
      } catch (e) {
        _log.warning('Serveur indisponible pour la dictée: $e');
        return false;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Raccourci
  // ---------------------------------------------------------------------------

  void _onShortcut(ShortcutEvent event) {
    if (!_enabled) return;
    switch (event) {
      case ShortcutEvent.pressed:
        _onPressed();
      case ShortcutEvent.released:
        _onReleased();
      case ShortcutEvent.cancel:
        if (_run case final _Run run when !run.finished) _cancel(run);
    }
  }

  void _onPressed() {
    // Réunion en train de démarrer : sa capture arrive, une capture de la
    // dictée la ferait échouer (une seule capture à la fois).
    if (_live.isStarting) return;
    final _Run? current = _run;
    if (current != null && !current.finished) {
      current.ignoreRelease = true;
      // Second appui d'une bascule : il arrête. Sinon (transcription) : ignoré.
      if (current.toggled && !current.captureEnded) _endCapture(current);
      return;
    }
    unawaited(_begin(current));
  }

  void _onReleased() {
    final _Run? run = _run;
    if (run == null || run.finished || run.captureEnded) return;
    if (run.ignoreRelease) {
      run.ignoreRelease = false;
      return;
    }
    if (clock.now().difference(run.pressedAt) < holdThreshold) {
      run.toggled = true; // appui bref : l'écoute continue
      return;
    }
    _endCapture(run);
  }

  Future<void> _begin(_Run? previous) async {
    final _Run run = _Run(clock.now());
    _run = run;
    unawaited(_shortcuts.setCancelKeyEnabled(true));
    _arbiter.dictationStarted();
    // Ancien flux resté ouvert après un délai de garde : fermé d'abord.
    if (previous != null && previous.streaming) {
      previous.late = false;
      await _closeStream(previous);
      if (run.finished) return;
    }
    if (_live.isRunning) {
      _beginInMeeting(run);
      return;
    }
    _set(
      run,
      _serverFree ? const DictationListening() : const DictationStarting(),
    );
    run.audio = _audio.audioStream.listen(
      (AudioChunk chunk) => _onChunk(run, chunk),
    );
    unawaited(_openStream(run));
    try {
      await _audio.startCapture(outputEnabled: false);
    } on PlatformException catch (e) {
      _log.warning('Capture de la dictée refusée: ${e.code}');
      _fail(run, DictationErrorReason.microphone);
    } catch (e) {
      _log.warning('Capture de la dictée échouée: $e');
      _fail(run, DictationErrorReason.microphone);
    }
  }

  bool get _serverFree =>
      _serverReady && _lending == null && !_live.isRecording;

  void _beginInMeeting(_Run run) {
    final MeetingDictation? handle = _live.beginDictation();
    if (handle == null) {
      // ponytail: réunion en pause ou dictée déjà ouverte : appui ignoré.
      _end(run, const DictationIdle());
      return;
    }
    run.meeting = handle;
    handle.onText = (String text, bool hadSpeech) =>
        _onText(run, text, hadSpeech);
    handle.onComplete = () => unawaited(_complete(run));
    _set(run, const DictationListening());
  }

  // ---------------------------------------------------------------------------
  // Flux propre (hors réunion)
  // ---------------------------------------------------------------------------

  void _onChunk(_Run run, AudioChunk chunk) {
    if (run.finished || run.captureEnded || chunk.source != AudioSource.input) {
      return;
    }
    if (run.streaming) {
      _remote.sendAudio(chunk);
      return;
    }
    run.buffer.add(chunk);
    if (run.buffer.length * _chunkMs >= maxStartingBuffer.inMilliseconds) {
      // Borne atteinte : la capture s'arrête comme au relâchement ; la touche
      // encore tenue n'y change plus rien.
      run.ignoreRelease = true;
      _endCapture(run);
    }
  }

  Future<void> _openStream(_Run run) async {
    if (!await _awaitServer(run)) {
      if (!run.finished) _fail(run, DictationErrorReason.serverUnavailable);
      return;
    }
    if (run.finished) return;
    try {
      await _remote.connect(url: _webSocketUrl, systemAudioEnabled: false);
    } catch (e) {
      _log.warning('Connexion de la dictée échouée: $e');
      _fail(run, DictationErrorReason.serverUnavailable);
      return;
    }
    if (run.finished) {
      await _remote.disconnect();
      return;
    }
    run.texts = _remote.transcriptionStream.listen(
      (TranscriptEventRemoteModel e) => _onRemoteEvent(run, e),
    );
    run.streaming = true;
    for (final AudioChunk chunk in run.buffer) {
      _remote.sendAudio(chunk);
    }
    run.buffer.clear();
    if (run.captureEnded) {
      _commit(run);
    } else {
      _set(run, const DictationListening());
    }
  }

  void _onRemoteEvent(_Run run, TranscriptEventRemoteModel event) {
    if (event.type != 'response.audio_transcript.done') return;
    _onText(run, event.text ?? '', _remote.windowOf(event)?.hadSpeech ?? true);
    if (run.committed &&
        !run.finished &&
        !_remote.activeSources.contains(AudioSource.input)) {
      unawaited(_complete(run));
    }
  }

  void _commit(_Run run) {
    run.committed = true;
    _remote.sendCommit(
      isFinal: true,
      sources: const <AudioSource>{AudioSource.input},
    );
    _startFinalTimer(run);
    if (!_remote.activeSources.contains(AudioSource.input)) {
      unawaited(_complete(run));
    }
  }

  Future<void> _closeStream(_Run run) async {
    if (!run.streaming) return;
    run.streaming = false;
    // Sans attendre : l'annulation depuis son propre callback ne rend la main
    // qu'à la fin de la diffusion.
    unawaited(run.texts?.cancel());
    await _remote.disconnect();
  }

  // ---------------------------------------------------------------------------
  // Fin de capture, texte, sortie
  // ---------------------------------------------------------------------------

  void _endCapture(_Run run) {
    if (run.captureEnded) return;
    run.captureEnded = true;
    _set(run, const DictationTranscribing());
    final MeetingDictation? meeting = run.meeting;
    if (meeting != null) {
      _startFinalTimer(run);
      meeting.release();
      return;
    }
    _stopCapture(run);
    if (run.streaming) _commit(run);
  }

  void _stopCapture(_Run run) {
    final StreamSubscription<AudioChunk>? audio = run.audio;
    if (audio == null) return;
    run.audio = null;
    unawaited(audio.cancel());
    unawaited(
      _audio.stopCapture().catchError((Object e) {
        _log.warning('Arrêt de la capture de la dictée: $e');
      }),
    );
  }

  void _startFinalTimer(_Run run) {
    run.finalTimer?.cancel();
    run.finalTimer = Timer(finalTextTimeout, () {
      if (run.finished) return;
      // Le flux reste ouvert : un texte tardif ira au presse-papiers.
      run.late = true;
      _end(run, const DictationError(DictationErrorReason.timeout));
      if (!run.ended.isCompleted) run.ended.complete();
    });
  }

  void _onText(_Run run, String raw, bool hadSpeech) {
    if (run.finished && !run.late) return;
    // Sans énergie de parole, rien n'a été dit : la phrase est écartée
    // (plus strict que la note, où seules les formules connues le sont).
    if (!hadSpeech) return;
    final String normalized = TranscriptTextNormalizer.normalize(raw);
    if (TranscriptTextNormalizer.isForeignScript(normalized)) return;
    final String? text = TranscriptTextNormalizer.filterFinalText(
      normalized,
      hadSpeechEnergy: true,
      previousTexts: run.kept,
    );
    if (text == null || text.trim().isEmpty) return;
    if (run.late) {
      run.late = false;
      unawaited(_deliverLate(run, text));
      return;
    }
    run.kept.add(text.trim());
  }

  Future<void> _deliverLate(_Run run, String text) async {
    await _closeStream(run);
    await _output.copy(text);
    if (identical(_run, run)) {
      _state.add(DictationDone(text, DictationDelivery.clipboardLate));
    }
  }

  Future<void> _complete(_Run run) async {
    if (run.finished) return;
    final String text = run.kept.join(' ').trim();
    _end(run, null);
    await _closeStream(run);
    if (text.isEmpty) {
      _state.add(const DictationNothingHeard());
    } else {
      _state.add(DictationDone(text, await _deliver(text)));
    }
    run.ended.complete();
  }

  Future<DictationDelivery> _deliver(String text) async {
    if (_settings?.outputMode != DictationOutputMode.paste) {
      await _output.copy(text);
      return DictationDelivery.clipboard;
    }
    // Lue au moment de la sortie : accordée pendant la dictée, elle compte.
    if (!await _output.isAccessibilityTrusted()) {
      await _output.copy(text);
      return DictationDelivery.clipboardNoAccessibility;
    }
    await _output.saveClipboard();
    await _output.copy(text);
    try {
      await _output.paste();
    } on PlatformException catch (e) {
      _log.warning('Collage refusé: ${e.code}');
      return DictationDelivery.clipboardPasteFailed;
    }
    Timer(pasteRestoreDelay, () => unawaited(_output.restoreClipboard()));
    return DictationDelivery.pasted;
  }

  void _cancel(_Run run) {
    run.meeting?.cancel();
    run.late = false;
    _end(run, const DictationIdle());
    unawaited(_closeStream(run));
    if (!run.ended.isCompleted) run.ended.complete();
  }

  void _fail(_Run run, DictationErrorReason reason) {
    _end(run, DictationError(reason));
    unawaited(_closeStream(run));
    if (!run.ended.isCompleted) run.ended.complete();
  }

  /// Fin de [run] : capture arrêtée, Échap libérée, serveur rendu à l'arbitre.
  void _end(_Run run, DictationState? state) {
    if (run.finished) return;
    run.finished = true;
    run.finalTimer?.cancel();
    _stopCapture(run);
    run.buffer.clear();
    unawaited(_shortcuts.setCancelKeyEnabled(false));
    _arbiter.dictationEnded();
    if (state != null) _state.add(state);
  }

  void _set(_Run run, DictationState state) {
    if (!run.finished && identical(_run, run)) _state.add(state);
  }

  /// Un enregistrement démarre : la dictée hors réunion se termine d'abord
  /// (texte produit), et son flux est fermé.
  Future<void> _handOverToRecording() async {
    // Démarrage du serveur en vol (lancement, fin d'emprunt) : la réunion
    // le trouve prêt au lieu d'en lancer un second (qui tuerait le premier).
    final Future<void>? starting = _serverStart;
    if (starting != null) await starting.catchError((Object _) {});
    final _Run? run = _run;
    if (run == null || run.meeting != null) return;
    if (!run.finished) {
      if (!run.streaming) {
        // ponytail: pas encore de flux (serveur pas prêt) : la dictée cède,
        // son audio n'est pas transcrit.
        _fail(run, DictationErrorReason.serverUnavailable);
        return;
      }
      _endCapture(run);
      await run.ended.future.timeout(finalTextTimeout, onTimeout: () {});
    }
    run.late = false;
    await _closeStream(run);
  }
}

/// Une dictée, de l'appui à sa fin.
final class _Run {
  _Run(this.pressedAt);

  final DateTime pressedAt;
  final Completer<void> ended = Completer<void>();
  final List<AudioChunk> buffer = <AudioChunk>[];
  final List<String> kept = <String>[];
  MeetingDictation? meeting;
  StreamSubscription<AudioChunk>? audio;
  StreamSubscription<TranscriptEventRemoteModel>? texts;
  Timer? finalTimer;
  bool toggled = false;
  bool ignoreRelease = false;
  bool captureEnded = false;
  bool committed = false;
  bool streaming = false;
  bool finished = false;

  /// Délai de garde passé : le prochain texte va au presse-papiers.
  bool late = false;
}
