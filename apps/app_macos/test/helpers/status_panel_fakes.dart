import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';

import 'fake_view_models.dart';

// Faux côté Swift du panneau de barre de menus (T3). Contrat du canal
// `com.icitranscript/status_panel` : voir l'en-tête de
// test/features/status_panel/status_panel_snapshot_test.dart.

const String kStatusPanelChannel = 'com.icitranscript/status_panel';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Panneau natif factice derrière `com.icitranscript/status_panel`.
class FakeStatusPanelPlatform {
  /// Tous les appels Dart → Swift, dans l'ordre.
  final List<MethodCall> calls = <MethodCall>[];

  /// Journal partageable avec d'autres faux (ordre entre eux).
  List<String> log = <String>[];

  /// Si non nul, chaque `update` lève cette erreur (puis le compteur
  /// [failUpdates] décroît ; 0 = de nouveau normal).
  int failUpdates = 0;

  /// Instantanés reçus par `update`, dans l'ordre.
  List<Map<Object?, Object?>> get updates => calls
      .where((MethodCall c) => c.method == 'update')
      .map((MethodCall c) => c.arguments as Map<Object?, Object?>)
      .toList();

  /// Dernier instantané reçu.
  Map<Object?, Object?> get last => updates.last;

  List<MethodCall> callsTo(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();

  void install() {
    _messenger.setMockMethodCallHandler(
      const MethodChannel(kStatusPanelChannel),
      (MethodCall call) async {
        calls.add(call);
        log.add('panel.${call.method}');
        if (call.method == 'update' && failUpdates > 0) {
          failUpdates--;
          throw PlatformException(code: 'PANEL_UNAVAILABLE');
        }
        return null;
      },
    );
    addTearDown(
      () => _messenger.setMockMethodCallHandler(
        const MethodChannel(kStatusPanelChannel),
        null,
      ),
    );
  }

  /// Le panneau natif envoie [method] (clic, ouverture, `ready`).
  Future<void> send(String method, [Object? args]) =>
      _messenger.handlePlatformMessage(
        kStatusPanelChannel,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (ByteData? _) {},
      );
}

/// Contrôleur de suggestion sans détection ni agenda : le test fixe la
/// suggestion affichée ; « Démarrer » et « Ignorer » restent les vrais
/// (`start()` → `startOrShowNote` avec l'événement, `dismiss()` → sourdine).
class PanelSuggestionController extends MeetingSuggestionController {
  int startCalls = 0;
  int dismissCalls = 0;

  @override
  MeetingSuggestion? build() => null;

  /// Fixe la suggestion affichée par le shell.
  void show(MeetingSuggestion? s) => state = s;

  @override
  Future<void> start() {
    startCalls++;
    return super.start();
  }

  @override
  void dismiss() {
    dismissCalls++;
    super.dismiss();
  }
}

/// Direct sans serveur : compte chaque action ; démarrage et arrêt peuvent
/// rester « en vol » (portes [startGate] / [stopGate]) pour tester un double
/// clic.
class PanelLiveViewModel extends FakeLiveTranscriptionViewModel {
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int skipCalls = 0;
  final List<CalendarEvent> linked = <CalendarEvent>[];

  /// Journal partageable (ordre arrêt / fin de l'app).
  List<String> log = <String>[];

  /// Si non nul, `startSession` attend ce futur avant de démarrer.
  Completer<void>? startGate;

  /// Si non nul, `stopSession` attend ce futur (vidange) avant de remettre
  /// l'état au repos.
  Completer<void>? stopGate;

  LiveTranscriptionState get current => state;

  @override
  void linkNextNoteTo(CalendarEvent event) => linked.add(event);

  /// Comme le vrai : l'état ne passe à « enregistre » qu'après une attente
  /// (post-traitement de la note précédente), ici [startGate].
  @override
  Future<void> startSession() async {
    await startGate?.future;
    await super.startSession();
    log.add('live.start');
  }

  @override
  Future<String?> stopSession() async {
    stopCalls++;
    log.add('live.stop');
    await stopGate?.future;
    state = state.copyWith(
      isRecording: false,
      isPaused: false,
      finalisingRemaining: null,
      duration: Duration.zero,
    );
    log.add('live.stopped');
    return 'note-1';
  }

  @override
  Future<void> pauseSession() async {
    pauseCalls++;
    state = state.copyWith(isPaused: true);
  }

  @override
  Future<void> resumeSession() async {
    resumeCalls++;
    state = state.copyWith(isPaused: false);
  }

  @override
  void skipFinalising() => skipCalls++;
}
