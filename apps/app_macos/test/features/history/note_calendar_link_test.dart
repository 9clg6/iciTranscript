import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoin 3, depuis la note : une note liée montre ses participants en
// puces ; le lien se retire ou se change depuis la note (choix parmi les
// événements du jour de la note) ; une note sans lien peut être liée.
// Vrai view model du détail, base Drift en mémoire, agenda factice.
//
// Repères supposés (fr.json) : `history.detail.calendar.unlink`,
// `history.detail.calendar.change`, `history.detail.calendar.link`,
// `history.detail.calendar.none` ; `common.action.cancel` ferme le choix.
// Un participant = un `OatsChip` portant son nom.
//
// Choix : retirer le lien garde le titre de la note ; changer (ou poser) le
// lien donne à la note le titre du nouvel événement.
final DateTime _noteStart = DateTime(2026, 11, 20, 10, 5);

void main() {
  late AppDatabase db;
  late FakeCalendarPlatform platform;

  Map<String, Object?> event(String id, String title, int hour) => eventJson(
    id: id,
    title: title,
    start: DateTime(2026, 11, 20, hour),
    end: DateTime(2026, 11, 20, hour, 45),
    attendees: <String>['Bérénice Roy', 'denis@example.com'],
  );

  Future<void> pumpNote(
    WidgetTester tester, {
    bool linked = true,
    bool connected = true,
    List<Map<String, Object?>>? events,
  }) async {
    resetPrefs();
    if (connected) {
      prefsFile.parent.createSync(recursive: true);
      prefsFile.writeAsStringSync(
        jsonEncode(<String, Object?>{'calendar_connected': true}),
      );
    }
    platform = FakeCalendarPlatform(
      status: 'fullAccess',
      events:
          events ??
          <Map<String, Object?>>[
            event('evt-comite', 'Comité produit', 10),
            event('evt-budget', 'Point budget', 14),
          ],
    )..install();
    db = memoryDatabase();
    addTearDown(db.close);
    final List<Override> overrides = <Override>[
      ...localModelOverrides(db, InstantOllamaService(installed: true)),
      apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
      llmDioProvider.overrideWithValue(
        Dio()..httpClientAdapter = RecordingHttpAdapter(),
      ),
      nowProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
    ];
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides);
      await c
          .read(sessionRepositoryProvider)
          .create(
            SessionEntity(
              id: 's1',
              title: linked ? 'Comité produit' : 'Session 2026-11-20 10:05',
              createdAt: _noteStart,
              updatedAt: _noteStart,
              durationSeconds: 1800,
              status: SessionStatus.completed,
              calendarEventId: linked ? 'evt-comite' : null,
              calendarEventTitle: linked ? 'Comité produit' : null,
              attendees: linked
                  ? const <String>['Alice Martin', 'Chloé Durand']
                  : const <String>[],
            ),
          );
      c.dispose();
    });
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: <Override>[
        ...overrides,
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(kOllamaReady),
        ),
      ],
    );
    await io(tester);
  }

  Future<SessionEntity> stored(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final ProviderContainer c = ProviderContainer(
          overrides: <Override>[
            ...localModelOverrides(db, InstantOllamaService(installed: true)),
          ],
        );
        final SessionEntity? s = await c
            .read(sessionRepositoryProvider)
            .getById('s1');
        c.dispose();
        return s;
      }))!;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await io(tester);
  }

  Finder chip(String name) =>
      find.descendant(of: find.byType(OatsChip), matching: find.text(name));

  testWidgets('une note liée montre ses participants en puces', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester);

    expect(chip('Alice Martin'), findsOneWidget);
    expect(chip('Chloé Durand'), findsOneWidget);
  });

  testWidgets('« Retirer le lien » : plus de lien ni de participants, '
      'le titre reste', (WidgetTester tester) async {
    await pumpNote(tester);

    await tapText(tester, 'history.detail.calendar.unlink'.tr());

    final SessionEntity s = await stored(tester);
    expect(s.calendarEventId, isNull);
    expect(s.calendarEventTitle, isNull);
    expect(s.attendees, isEmpty);
    expect(s.title, 'Comité produit');
    expect(chip('Alice Martin'), findsNothing);
  });

  testWidgets('« Changer d\'événement » propose les événements du jour de la '
      'note et lie celui choisi', (WidgetTester tester) async {
    await pumpNote(tester);

    await tapText(tester, 'history.detail.calendar.change'.tr());

    final Map<Object?, Object?> range =
        platform.callsTo('events').last.arguments as Map<Object?, Object?>;
    expect(
      range['from']! as int,
      lessThanOrEqualTo(DateTime(2026, 11, 20).millisecondsSinceEpoch),
    );
    expect(
      range['to']! as int,
      greaterThanOrEqualTo(DateTime(2026, 11, 21).millisecondsSinceEpoch),
    );
    expect(find.text('Point budget'), findsOneWidget);

    await tapText(tester, 'Point budget');

    final SessionEntity s = await stored(tester);
    expect(s.calendarEventId, 'evt-budget');
    expect(s.calendarEventTitle, 'Point budget');
    expect(s.title, 'Point budget');
    expect(s.attendees, <String>['Bérénice Roy']);
    expect(chip('Bérénice Roy'), findsOneWidget);
    expect(find.textContaining('denis@example.com'), findsNothing);
  });

  testWidgets('choix annulé : le lien ne change pas', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester);

    await tapText(tester, 'history.detail.calendar.change'.tr());
    await tapText(tester, 'common.action.cancel'.tr());

    expect((await stored(tester)).calendarEventId, 'evt-comite');
    expect(chip('Alice Martin'), findsOneWidget);
  });

  testWidgets('une note sans lien peut être liée à un événement de son jour', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, linked: false);

    await tapText(tester, 'history.detail.calendar.link'.tr());
    await tapText(tester, 'Comité produit');

    final SessionEntity s = await stored(tester);
    expect(s.calendarEventId, 'evt-comite');
    expect(s.title, 'Comité produit');
  });

  testWidgets('aucun événement ce jour-là : le choix le dit', (
    WidgetTester tester,
  ) async {
    await pumpNote(
      tester,
      linked: false,
      events: const <Map<String, Object?>>[],
    );

    await tapText(tester, 'history.detail.calendar.link'.tr());

    expect(
      find.textContaining('history.detail.calendar.none'.tr()),
      findsOneWidget,
    );
  });

  testWidgets('agenda non connecté : pas de « Lier », rien lu', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, linked: false, connected: false);

    expect(find.text('history.detail.calendar.link'.tr()), findsNothing);
    expect(platform.dataReads, isEmpty);
  });

  testWidgets('agenda non connecté : une note liée garde ses puces et '
      'peut perdre son lien', (WidgetTester tester) async {
    await pumpNote(tester, connected: false);

    expect(chip('Alice Martin'), findsOneWidget);
    await tapText(tester, 'history.detail.calendar.unlink'.tr());

    expect((await stored(tester)).calendarEventId, isNull);
    expect(platform.dataReads, isEmpty);
  });
}

/// Laisse passer les vraies E/S (Drift, prefs.json) puis quelques images.
Future<void> io(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
