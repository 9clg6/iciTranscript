import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoins 3, 6 et 8, avec le vrai contrôleur de suggestion et le vrai
// view model du direct (serveur, micro, socket factices) :
// - « Démarrer la note » d'une suggestion d'agenda lie l'événement AFFICHÉ
//   dans l'invite, même quand un autre événement est plus proche au moment
//   du clic (là où `eventToLink` en choisirait un autre) ; idem pour le
//   démarrage automatique (mode `auto`) ;
// - afficher ou ignorer une suggestion n'écrit dans le journal ni titre
//   d'événement, ni participant, ni nom d'app d'appel (seul un bundle id
//   inconnu peut y figurer, id seul).
//
// API : `meetingSuggestionControllerProvider` (state =
// `MeetingSuggestion?`, `start()`, `dismiss()`), `nowProvider`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPrefs);
  tearDown(resetPrefs);

  late LiveServiceHarness harness;
  late ProviderContainer c;
  late DateTime now;

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
  }

  MeetingSuggestion? shown() => c.read(meetingSuggestionControllerProvider);

  // Atelier en cours depuis 10 min (suggéré tout de suite) ; Point client
  // commence 4 min plus tard (pas encore suggéré). Au clic, 3 min 30 plus
  // tard, Point client commence dans 30 s : plus proche que l'Atelier.
  final DateTime t0 = DateTime(2026, 11, 23, 10);
  List<Map<String, Object?>> overlapping() => <Map<String, Object?>>[
    eventJson(
      id: 'evt-atelier',
      title: 'Atelier stratégie',
      start: t0.subtract(const Duration(minutes: 10)),
      end: t0.add(const Duration(minutes: 50)),
      attendees: <String>['Alice Martin', 'Bruno Petit'],
    ),
    eventJson(
      id: 'evt-client',
      title: 'Point client',
      start: t0.add(const Duration(minutes: 4)),
      end: t0.add(const Duration(minutes: 30)),
      attendees: <String>['Chloé Durand', 'Denis Roy'],
    ),
  ];

  Future<SessionEntity> session() async {
    await eventually(() => expect(harness.sessions.store.values, hasLength(1)));
    return harness.sessions.store.values.single;
  }

  test('« Démarrer la note » lie l\'événement affiché, pas le plus proche '
      'au moment du clic', () async {
    now = t0;
    writePrefs(<String, Object?>{'calendar_connected': true});
    FakeCalendarPlatform(status: 'fullAccess', events: overlapping()).install();
    FakeMeetingPlatform().install();
    await launch();
    await eventually(() => expect(shown()?.event?.id, 'evt-atelier'));

    now = t0.add(const Duration(minutes: 3, seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(shown()?.event?.id, 'evt-atelier', reason: 'invite inchangée');

    unawaited(c.read(meetingSuggestionControllerProvider.notifier).start());

    await eventually(() async {
      final SessionEntity s = await session();
      expect(s.calendarEventId, 'evt-atelier');
    });
    final SessionEntity s = await session();
    expect(s.title, 'Atelier stratégie');
    expect(s.attendees, <String>['Alice Martin', 'Bruno Petit']);
  });

  test(
    'mode auto : la note démarrée lie l\'événement qui l\'a déclenchée',
    () async {
      // À t0 seul l'Atelier est suggérable ; Point client commence dans
      // 4 min, hors de la minute d'avance.
      now = t0;
      writePrefs(<String, Object?>{
        'calendar_connected': true,
        'meeting_detection_mode': 'auto',
      });
      FakeCalendarPlatform(
        status: 'fullAccess',
        events: overlapping(),
      ).install();
      FakeMeetingPlatform().install();
      await launch();

      await eventually(() async {
        expect((await session()).calendarEventId, 'evt-atelier');
      });
    },
  );

  group('journal', () {
    late String path;

    setUp(() {
      final Directory dir = Directory.systemTemp.createTempSync('oats-log');
      path = '${dir.path}/oats.log';
      Log.writeToFile(path);
    });

    Future<String> log() async {
      Log.named('Sonde').info('fin du test');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final String text = File(path).readAsStringSync();
      expect(text, contains('fin du test'), reason: 'le journal est capté');
      return text;
    }

    test('suggestion d\'agenda affichée puis ignorée : ni titre ni '
        'participant au journal', () async {
      now = t0;
      writePrefs(<String, Object?>{'calendar_connected': true});
      FakeCalendarPlatform(
        status: 'fullAccess',
        events: overlapping(),
      ).install();
      FakeMeetingPlatform().install();
      await launch();
      await eventually(() => expect(shown(), isNotNull));

      c.read(meetingSuggestionControllerProvider.notifier).dismiss();
      final String text = await log();

      for (final String secret in <String>[
        'Atelier stratégie',
        'Point client',
        'Alice',
        'Bruno',
        'Chloé',
        'Denis',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('appel détecté affiché puis ignoré : pas de nom d\'app au journal ; '
        'un bundle id inconnu peut y figurer, seul', () async {
      now = t0;
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      FakeCalendarPlatform().install();
      await launch();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await mic.micUsers(<String>['us.zoom.xos', 'com.example.recorder']);
      now = t0.add(const Duration(seconds: 4));
      await eventually(() => expect(shown()?.appName, 'Zoom'));
      c.read(meetingSuggestionControllerProvider.notifier).dismiss();
      final String text = await log();

      expect(text, isNot(contains('Zoom')));
      expect(text, isNot(contains('us.zoom.xos')));
      for (final String line in text.split('\n')) {
        if (line.contains('com.example.recorder')) {
          expect(
            line.replaceAll('com.example.recorder', ''),
            isNot(contains(RegExp(r'[A-Za-z0-9-]+\.[A-Za-z0-9-]+\.'))),
            reason: 'id seul, sans autre bundle id : $line',
          );
        }
      }
    });
  });
}
