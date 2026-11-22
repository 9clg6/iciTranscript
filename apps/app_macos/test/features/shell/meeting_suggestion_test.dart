import 'dart:convert';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoins 5 à 7, vus depuis l'application entière : la suggestion de
// démarrer une note est une invite non bloquante (le reste de l'app reste
// utilisable), titrée par l'événement ou « Appel détecté » + le nom de
// l'app, avec « Démarrer la note » et « Ignorer ». Elle disparaît quand
// l'app d'appel lâche le micro ou quand l'événement est fini. Détection
// coupée : rien. Mode « auto » : un événement de l'agenda démarre la note
// sans demander (un appel détecté demande toujours).
//
// Repères supposés (fr.json) : `meeting.suggestion.call_title`,
// `meeting.suggestion.start`, `meeting.suggestion.dismiss`. Le nom de l'app
// (« Zoom ») et le titre de l'événement sont affichés tels quels.
// Démarrer passe par LiveTranscriptionViewModel.startSession() (le lien
// suit la règle 3, spécifiée dans start_note_link_test.dart).
final DateTime _anchor = DateTime(2026, 11, 23, 10);

void main() {
  setUp(resetPrefs);

  void writePrefs(Map<String, Object?> prefs) {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(jsonEncode(prefs));
  }

  Future<AppFakes> pumpApp(
    WidgetTester tester, {
    List<SessionEntity> sessions = const <SessionEntity>[],
  }) async {
    final AppFakes f = AppFakes(sessions: sessions, ollama: kOllamaReady);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: <Override>[
          ...f.overrides,
          nowProvider.overrideWithValue(widgetClock(tester, _anchor)),
        ],
        withMaterialApp: false,
      ),
    );
    await settle(tester);
    return f;
  }

  final Finder callTitle = find.text('meeting.suggestion.call_title'.tr());
  final Finder startButton = find.text('meeting.suggestion.start'.tr());
  final Finder dismissButton = find.text('meeting.suggestion.dismiss'.tr());

  Future<void> hold(
    WidgetTester tester,
    FakeMeetingPlatform mic,
    List<String> ids,
    Duration duration,
  ) async {
    await mic.micUsers(ids);
    await tester.pump(duration);
    await settle(tester);
  }

  group('appel détecté par le micro', () {
    testWidgets('Zoom tient le micro 3 s : « Appel détecté », Zoom, '
        'Démarrer et Ignorer', (WidgetTester tester) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);

      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 1));
      expect(callTitle, findsNothing, reason: 'pas avant 3 s');

      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(callTitle, findsOneWidget);
      expect(find.textContaining('Zoom'), findsWidgets);
      expect(startButton, findsOneWidget);
      expect(dismissButton, findsOneWidget);
    });

    testWidgets('« Démarrer la note » lance l\'enregistrement et ferme '
        'l\'invite', (WidgetTester tester) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      final AppFakes f = await pumpApp(tester);
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));

      await tester.tap(startButton);
      await settle(tester);

      expect(f.live.startCalls, 1);
      expect(callTitle, findsNothing);
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(RootAppWidget)),
      );
      expect(c.read(shellViewControllerProvider), ShellView.live);
    });

    testWidgets('« Ignorer » ferme l\'invite ; un nouvel appel dans les '
        '10 minutes ne redemande pas, après 10 minutes oui', (
      WidgetTester tester,
    ) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      final AppFakes f = await pumpApp(tester);
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));

      await tester.tap(dismissButton);
      await settle(tester);
      expect(callTitle, findsNothing);
      expect(f.live.startCalls, 0);

      await hold(tester, mic, <String>[], const Duration(seconds: 1));
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(minutes: 5));
      expect(callTitle, findsNothing, reason: 'en sourdine 10 min');

      await hold(tester, mic, <String>[], const Duration(seconds: 1));
      await tester.pump(const Duration(minutes: 5));
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));
      expect(callTitle, findsOneWidget);
    });

    testWidgets('l\'app lâche le micro : l\'invite disparaît', (
      WidgetTester tester,
    ) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));
      expect(callTitle, findsOneWidget);

      await hold(tester, mic, <String>[], const Duration(seconds: 1));

      expect(callTitle, findsNothing);
    });

    testWidgets('la même prise de micro ne redemande pas après Ignorer, même '
        '10 minutes plus tard', (WidgetTester tester) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));
      await tester.tap(dismissButton);
      await settle(tester);

      await tester.pump(const Duration(minutes: 11));
      await settle(tester);

      expect(callTitle, findsNothing);
    });

    testWidgets('une app inconnue qui tient le micro : rien', (
      WidgetTester tester,
    ) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);

      await hold(tester, mic, <String>[
        'com.example.recorder',
      ], const Duration(seconds: 10));

      expect(callTitle, findsNothing);
      expect(startButton, findsNothing);
    });

    testWidgets('pendant qu\'Oats enregistre : rien', (
      WidgetTester tester,
    ) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      final AppFakes f = await pumpApp(tester);
      f.live.show(LiveTranscriptionState.initial().copyWith(isRecording: true));
      await settle(tester);

      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 10));

      expect(callTitle, findsNothing);
    });

    testWidgets('détection coupée dans Réglages : rien', (
      WidgetTester tester,
    ) async {
      writePrefs(<String, Object?>{'meeting_detection_enabled': false});
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);

      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 10));

      expect(callTitle, findsNothing);
    });

    testWidgets('invite non bloquante : la barre latérale reste utilisable', (
      WidgetTester tester,
    ) async {
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      await pumpApp(tester);
      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));

      final Finder documents = find.descendant(
        of: find.byKey(const ValueKey<String>('oats-sidebar')),
        matching: find.text('nav.documents'.tr()),
      );
      expect(isOnScreen(documents), isTrue);
      await tester.tap(documents);
      await settle(tester);

      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(RootAppWidget)),
      );
      expect(c.read(shellViewControllerProvider), ShellView.documents);
      expect(callTitle, findsOneWidget);
    });

    testWidgets('mode auto : un appel détecté demande quand même', (
      WidgetTester tester,
    ) async {
      writePrefs(<String, Object?>{'meeting_detection_mode': 'auto'});
      final FakeMeetingPlatform mic = FakeMeetingPlatform()..install();
      final AppFakes f = await pumpApp(tester);

      await hold(tester, mic, <String>[
        'us.zoom.xos',
      ], const Duration(seconds: 4));

      expect(callTitle, findsOneWidget);
      expect(f.live.startCalls, 0);
    });
  });

  group('événement de l\'agenda', () {
    Map<String, Object?> standup({
      DateTime? start,
      List<String> attendees = const <String>['Alice', 'Bruno'],
    }) {
      final DateTime s = start ?? _anchor.add(const Duration(seconds: 30));
      return eventJson(
        id: 'evt-standup',
        title: 'Stand-up équipe',
        start: s,
        end: s.add(const Duration(minutes: 15)),
        attendees: attendees,
      );
    }

    FakeCalendarPlatform connected(List<Map<String, Object?>> events) {
      writePrefs(<String, Object?>{'calendar_connected': true});
      return FakeCalendarPlatform(status: 'fullAccess', events: events)
        ..install();
    }

    // Sur Documents, le bloc « À venir » de l'accueil (même titre, bouton
    // « Démarrer la note » des événements en cours) n'est pas affiché : ce
    // qui reste vient de l'invite.
    Future<void> goToDocuments(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('oats-sidebar')),
          matching: find.text('nav.documents'.tr()),
        ),
      );
      await settle(tester);
    }

    testWidgets('commence dans 30 s, 2 participants : invite au titre de '
        'l\'événement', (WidgetTester tester) async {
      connected(<Map<String, Object?>>[standup()]);
      FakeMeetingPlatform().install();

      await pumpApp(tester);
      await goToDocuments(tester);

      expect(startButton, findsOneWidget);
      expect(find.text('Stand-up équipe'), findsOneWidget);
    });

    testWidgets('un seul participant : pas d\'invite', (
      WidgetTester tester,
    ) async {
      connected(<Map<String, Object?>>[
        standup(attendees: const <String>['Alice']),
      ]);
      FakeMeetingPlatform().install();

      await pumpApp(tester);
      await goToDocuments(tester);

      expect(startButton, findsNothing);
    });

    testWidgets('en cours mais une note existe déjà pour lui : pas d\'invite', (
      WidgetTester tester,
    ) async {
      connected(<Map<String, Object?>>[
        standup(start: _anchor.subtract(const Duration(minutes: 5))),
      ]);
      FakeMeetingPlatform().install();
      final DateTime t = _anchor.subtract(const Duration(minutes: 4));

      await pumpApp(
        tester,
        sessions: <SessionEntity>[
          SessionEntity(
            id: 's1',
            title: 'Stand-up équipe',
            createdAt: t,
            updatedAt: t,
            status: SessionStatus.completed,
            calendarEventId: 'evt-standup',
            calendarEventTitle: 'Stand-up équipe',
          ),
        ],
      );
      await goToDocuments(tester);

      expect(startButton, findsNothing);
    });

    testWidgets('l\'événement se termine : l\'invite disparaît', (
      WidgetTester tester,
    ) async {
      connected(<Map<String, Object?>>[standup()]);
      FakeMeetingPlatform().install();
      await pumpApp(tester);
      await goToDocuments(tester);
      expect(startButton, findsOneWidget);

      await tester.pump(const Duration(minutes: 16));
      await settle(tester);

      expect(startButton, findsNothing);
    });

    testWidgets('mode auto : la note démarre sans invite', (
      WidgetTester tester,
    ) async {
      connected(<Map<String, Object?>>[standup()]);
      writePrefs(<String, Object?>{
        'calendar_connected': true,
        'meeting_detection_mode': 'auto',
      });
      FakeMeetingPlatform().install();

      final AppFakes f = await pumpApp(tester);
      await goToDocuments(tester);

      expect(f.live.startCalls, 1);
      expect(startButton, findsNothing);
    });

    testWidgets('macOS < 14 : les suggestions de l\'agenda restent', (
      WidgetTester tester,
    ) async {
      connected(<Map<String, Object?>>[standup()]);
      FakeMeetingPlatform(supported: false).install();

      await pumpApp(tester);
      await goToDocuments(tester);

      expect(startButton, findsOneWidget);
    });

    testWidgets('agenda non connecté : aucune invite d\'agenda, rien lu', (
      WidgetTester tester,
    ) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[standup()],
      )..install();
      FakeMeetingPlatform().install();

      await pumpApp(tester);
      await goToDocuments(tester);

      expect(startButton, findsNothing);
      expect(platform.dataReads, isEmpty);
    });
  });
}
