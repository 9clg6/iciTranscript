import 'dart:convert';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoin 5 (« never while Oats itself is recording or dictating ») avec
// la dictée de main :
// - une dictée est en cours dans les états DictationStarting, Listening et
//   Transcribing (`isDictating`), pas dans les autres ;
// - pendant une dictée, aucune suggestion (agenda ou micro) n'apparaît et
//   rien ne démarre seul (mode auto compris) ; le micro pris par Oats (son
//   bundle id ou un auxiliaire) ne compte jamais comme un appel ;
// - une suggestion déjà à l'écran quand la dictée commence reste affichée et
//   peut être ignorée ; elle ne démarre rien d'elle-même ;
// - à la fin de la dictée, une suggestion toujours valable (événement en
//   cours, appel qui tient encore le micro) apparaît sans attendre la
//   sourdine de 10 minutes : l'utilisateur ne l'a pas ignorée.
//
// Entrée « dicte » : `dictationActiveProvider` (alimenté par
// `DictationController.stateStream` via `isDictating`) ; vrai contrôleur de
// suggestion, vrai view model du direct sur faux serveur.
// Non couvert ici : le branchement stateStream → dictationActiveProvider
// (le vrai contrôleur de dictée exige le modèle de transcription en cache).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPrefs);
  tearDown(resetPrefs);

  group('isDictating', () {
    final Map<DictationState, bool> cases = <DictationState, bool>{
      const DictationIdle(): false,
      const DictationStarting(): true,
      const DictationListening(): true,
      const DictationTranscribing(): true,
      const DictationDone('Bonjour', DictationDelivery.pasted): false,
      const DictationNothingHeard(): false,
      const DictationModelMissing(): false,
      const DictationError(DictationErrorReason.timeout): false,
    };
    cases.forEach((DictationState s, bool expected) {
      test('${s.runtimeType} → $expected', () {
        expect(isDictating(s), expected);
      });
    });
  });

  late LiveServiceHarness harness;
  late ProviderContainer c;
  late DateTime now;
  final DateTime t0 = DateTime(2026, 11, 23, 10);

  void writePrefs(Map<String, Object?> prefs) {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(jsonEncode(prefs));
  }

  Future<void> launch() async {
    harness = LiveServiceHarness(FakeAsync());
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(harness.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: harness.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(const <SessionEntity>[]),
        ),
        nowProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.read(liveTranscriptionViewModelProvider);
    c.listen(meetingSuggestionControllerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  MeetingSuggestion? shown() => c.read(meetingSuggestionControllerProvider);
  void dictating(bool on) => c.read(dictationActiveProvider.notifier).set(on);

  /// Laisse tourner l'évaluation (une par seconde) un peu plus d'un tour.
  Future<void> tick() =>
      Future<void>.delayed(const Duration(milliseconds: 1500));

  Map<String, Object?> atelier() => eventJson(
    id: 'evt-atelier',
    title: 'Atelier stratégie',
    start: t0.subtract(const Duration(minutes: 5)),
    end: t0.add(const Duration(minutes: 55)),
    attendees: <String>['Alice Martin', 'Bruno Petit'],
  );

  FakeMeetingPlatform withCalendar({bool auto = false}) {
    writePrefs(<String, Object?>{
      'calendar_connected': true,
      if (auto) 'meeting_detection_mode': 'auto',
    });
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[atelier()],
    ).install();
    return FakeMeetingPlatform()..install();
  }

  FakeMeetingPlatform withoutCalendar() {
    FakeCalendarPlatform().install();
    return FakeMeetingPlatform()..install();
  }

  /// Zoom prend le micro maintenant ; 4 s plus tard (horloge d'Oats).
  Future<void> zoomHolds(FakeMeetingPlatform mic) async {
    await mic.micUsers(<String>['us.zoom.xos']);
    now = now.add(const Duration(seconds: 4));
    await tick();
  }

  group('pendant une dictée', () {
    test('événement en cours : aucune suggestion', () async {
      now = t0;
      withCalendar();
      await launch();
      dictating(true);

      await tick();
      await tick();

      expect(shown(), isNull);
    });

    test('mode auto : rien ne démarre seul', () async {
      now = t0;
      withCalendar(auto: true);
      await launch();
      dictating(true);

      await tick();
      await tick();

      expect(harness.sessions.store, isEmpty);
    });

    test('Zoom tient le micro : aucune suggestion', () async {
      now = t0;
      final FakeMeetingPlatform mic = withoutCalendar();
      await launch();
      dictating(true);

      await zoomHolds(mic);

      expect(shown(), isNull);
    });

    test('le micro pris par Oats (son id ou un auxiliaire) n\'est jamais un '
        'appel, ni pendant ni après la dictée', () async {
      now = t0;
      final FakeMeetingPlatform mic = withoutCalendar();
      await launch();
      dictating(true);

      await mic.micUsers(<String>[kOwnBundleId, '$kOwnBundleId.helper']);
      now = now.add(const Duration(seconds: 10));
      await tick();
      expect(shown(), isNull);

      dictating(false);
      now = now.add(const Duration(seconds: 10));
      await tick();
      expect(shown(), isNull);
    });
  });

  group('suggestion déjà à l\'écran', () {
    test('elle reste quand la dictée commence, et peut être ignorée', () async {
      now = t0;
      final FakeMeetingPlatform mic = withoutCalendar();
      await launch();
      await zoomHolds(mic);
      expect(shown()?.appName, 'Zoom');

      dictating(true);
      await tick();
      expect(shown()?.appName, 'Zoom', reason: 'reste affichée');

      c.read(meetingSuggestionControllerProvider.notifier).dismiss();
      expect(shown(), isNull);
      expect(harness.sessions.store, isEmpty);
    });

    test('elle ne démarre rien d\'elle-même pendant la dictée', () async {
      now = t0;
      withCalendar();
      await launch();
      await eventually(() => expect(shown()?.event?.id, 'evt-atelier'));

      dictating(true);
      await tick();
      await tick();

      expect(harness.sessions.store, isEmpty);
    });
  });

  group('fin de la dictée', () {
    test('événement toujours en cours : la suggestion apparaît', () async {
      now = t0;
      withCalendar();
      await launch();
      dictating(true);
      await tick();
      expect(shown(), isNull);

      dictating(false);
      now = now.add(const Duration(seconds: 30));
      await tick();

      expect(shown()?.event?.id, 'evt-atelier');
    });

    test('Zoom tient toujours le micro : la suggestion apparaît, sans '
        'sourdine de 10 minutes', () async {
      now = t0;
      final FakeMeetingPlatform mic = withoutCalendar();
      await launch();
      dictating(true);
      await zoomHolds(mic);
      expect(shown(), isNull);

      dictating(false);
      now = now.add(const Duration(seconds: 2));
      await tick();

      expect(shown()?.appName, 'Zoom');
    });

    test('une suggestion masquée par la dictée revient à sa fin', () async {
      // Si l'implémentation masque l'invite au début de la dictée (au lieu
      // de la garder), elle doit revenir : l'utilisateur ne l'a pas ignorée.
      now = t0;
      final FakeMeetingPlatform mic = withoutCalendar();
      await launch();
      await zoomHolds(mic);
      expect(shown()?.appName, 'Zoom');

      dictating(true);
      await tick();
      dictating(false);
      now = now.add(const Duration(seconds: 2));
      await tick();

      expect(shown()?.appName, 'Zoom');
    });
  });
}
