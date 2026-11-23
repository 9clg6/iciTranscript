import 'dart:async';
import 'dart:convert';

import 'package:core_foundation/logging/logger.dart';
import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/start_note.dart';
import 'package:ici_transcript/features/status_panel/status_panel_snapshot.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'status_panel_sync.provider.g.dart';

/// Canal du panneau de barre de menus (StatusPanelPlugin.swift).
const MethodChannel kStatusPanelChannel = MethodChannel(
  'com.icitranscript/status_panel',
);

/// Écart minimal entre deux envois : ~4 par seconde pendant un flux, le
/// dernier état toujours envoyé à la fin.
const Duration kStatusPanelThrottle = Duration(milliseconds: 250);

/// Tient le panneau de barre de menus à jour et exécute ses clics. Monté par
/// l'app (RootAppWidget) pour toute sa vie.
@Riverpod(keepAlive: true)
StatusPanelSync statusPanelSync(Ref ref) {
  final StatusPanelSync sync = StatusPanelSync._(ref);
  ref.onDispose(sync._dispose);
  return sync;
}

/// Voir [statusPanelSync].
class StatusPanelSync {
  StatusPanelSync._(this._ref) {
    kStatusPanelChannel.setMethodCallHandler(_onCall);
    _ref.listen(liveTranscriptionViewModelProvider, (_, _) => _changed());
    _ref.listen(meetingSuggestionControllerProvider, (_, _) => _changed());
    _ref.listen(dictationActiveProvider, (_, _) => _changed());
    _questions = _answers.questionsStream.listen((_) => _changed());
    _send(force: true);
  }

  final Ref _ref;
  final Log _log = Log.named('StatusPanel');
  late final StreamSubscription<List<LiveQuestion>> _questions;
  Timer? _cooldown;
  bool _dirty = false;
  String? _lastSent;
  Future<void>? _starting;
  Future<void>? _stopping;
  final List<Completer<void>> _idleWaiters = <Completer<void>>[];

  LiveAnswersService get _answers => _ref.read(liveAnswersServiceProvider);
  LiveTranscriptionState get _live =>
      _ref.read(liveTranscriptionViewModelProvider);
  LiveTranscriptionViewModel get _liveVm =>
      _ref.read(liveTranscriptionViewModelProvider.notifier);

  Map<String, Object?> _snapshot() => statusPanelSnapshot(
    live: _live,
    questions: _answers.questions,
    suggestion: _ref.read(meetingSuggestionControllerProvider),
    dictating: _ref.read(dictationActiveProvider),
  );

  bool get _idle =>
      !_live.isRecording && !_live.isPaused && _live.finalisingRemaining == null;

  void _changed() {
    if (_idle) {
      for (final Completer<void> c in _idleWaiters) {
        c.complete();
      }
      _idleWaiters.clear();
    }
    if (_cooldown != null) {
      _dirty = true;
      return;
    }
    _send();
  }

  /// Envoie l'instantané s'il a changé ([force] : même inchangé), puis
  /// ouvre une période de [kStatusPanelThrottle] où les changements
  /// attendent.
  void _send({bool force = false}) {
    _dirty = false;
    final Map<String, Object?> snapshot = _snapshot();
    final String encoded = jsonEncode(snapshot);
    if (!force && encoded == _lastSent) return;
    _lastSent = encoded;
    unawaited(_invoke('update', snapshot));
    _cooldown?.cancel();
    _cooldown = Timer(kStatusPanelThrottle, () {
      _cooldown = null;
      if (_dirty) _send();
    });
  }

  /// Panneau absent (tests, plugin non chargé) ou en erreur : rien ne
  /// remonte ; jamais les arguments au journal (textes de la réunion).
  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await kStatusPanelChannel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Pas de panneau natif.
    } on PlatformException catch (e) {
      _log.warning('Panneau : $method refusé (${e.code})');
    }
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        _send(force: true);
      case 'start':
        await _start(() => startOrShowNote(_ref.read));
      case 'acceptSuggestion':
        final MeetingSuggestionController suggestion = _ref.read(
          meetingSuggestionControllerProvider.notifier,
        );
        if (_ref.read(meetingSuggestionControllerProvider) == null) return;
        await _start(suggestion.start);
      case 'dismissSuggestion':
        if (_ref.read(meetingSuggestionControllerProvider) == null) return;
        _ref.read(meetingSuggestionControllerProvider.notifier).dismiss();
      case 'stop':
        await _stop();
      case 'pauseResume':
        if (_live.finalisingRemaining != null) return;
        if (_live.isPaused) {
          await _liveVm.resumeSession();
        } else if (_live.isRecording) {
          await _liveVm.pauseSession();
        }
      case 'skipFinalising':
        if (_live.finalisingRemaining != null) _liveVm.skipFinalising();
      case 'answerNow':
        final Object? id = (call.arguments as Map<Object?, Object?>?)?[
          'questionId'];
        // `retry` efface une réponse reçue : seulement une question à
        // demander.
        if (_answers.questions.any(
          (LiveQuestion q) =>
              q.id == id && q.status == LiveQuestionStatus.detected,
        )) {
          _answers.retry(id! as String);
        }
      case 'openWindow':
        await _invoke('showWindow');
      case 'quit':
        await _stop();
        // Arrêt lancé depuis la fenêtre et encore en finalisation : on
        // attend aussi, la note se sauve avant la fin de l'app.
        if (!_idle) {
          final Completer<void> idle = Completer<void>();
          _idleWaiters.add(idle);
          await idle.future;
        }
        await _invoke('terminate');
    }
  }

  /// Un seul démarrage à la fois (double clic, Démarrer + suggestion).
  Future<void> _start(Future<void> Function() start) {
    return _starting ??= start().whenComplete(() => _starting = null);
  }

  /// Arrête la note en cours, une seule fois ; rien au repos ni pendant la
  /// finalisation. N'ouvre pas la note.
  Future<void> _stop() {
    final Future<void>? inFlight = _stopping;
    if (inFlight != null) return inFlight;
    if (_live.finalisingRemaining != null ||
        !(_live.isRecording || _live.isPaused)) {
      return Future<void>.value();
    }
    return _stopping = _liveVm.stopSession().then<void>((_) {}).whenComplete(
      () => _stopping = null,
    );
  }

  void _dispose() {
    kStatusPanelChannel.setMethodCallHandler(null);
    _cooldown?.cancel();
    unawaited(_questions.cancel());
  }
}
