import 'dart:convert';

import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

// T5, partie C : section « Agenda et réunions » de Réglages. Connexion et
// déconnexion, agendas inclus (défaut : tous), détection on/off (défaut :
// on), « démarrer automatiquement » pour les événements de l'agenda (défaut :
// demander), note macOS < 14. Tout est rangé dans prefs.json et survit à un
// redémarrage.
//
// Repères supposés (textes de fr.json) :
// - titre de section `settings.calendar.title` ;
// - boutons `settings.calendar.connect`, `settings.calendar.disconnect`,
//   `settings.calendar.open_settings` ; refus : `settings.calendar.denied` ;
// - une ligne par agenda : son titre et un `OatsSwitch` sur la même `Row` ;
// - `settings.calendar.detection` et `settings.calendar.auto_start` : chacun
//   un `OatsSwitch` sur la même `Row` que son libellé ;
// - macOS < 14 (canal de détection `start` → false) :
//   `settings.calendar.mic_unsupported`.
// prefs.json : `calendar_connected` (bool), `calendar_ids` (List<String>,
// absent = tous ; retiré quand tous sont de nouveau cochés, pour qu'un
// agenda ajouté plus tard soit inclus), `meeting_detection_enabled` (bool,
// absent = true), `meeting_detection_mode` (`ask` | `auto`, absent = ask).
void main() {
  setUp(resetPrefs);

  List<Override> overrides(WidgetTester tester) => <Override>[
    apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
    llmDioProvider.overrideWithValue(
      Dio()..httpClientAdapter = RecordingHttpAdapter(),
    ),
    audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
    liveTranscriptionViewModelProvider.overrideWith(
      FakeLiveTranscriptionViewModel.new,
    ),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
    nowProvider.overrideWithValue(
      widgetClock(tester, DateTime(2026, 11, 23, 10)),
    ),
  ];

  Future<void> io(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Ouvre Réglages ; deux appels dans un test = redémarrage.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLocalized(
      tester,
      const SettingsScreen(),
      overrides: overrides(tester),
      size: const Size(1280, 5000),
      settle: false,
    );
    for (int i = 0; i < 40; i++) {
      if (find.text(appDataDirectory()).evaluate().isNotEmpty) break;
      await io(tester);
    }
    await io(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await tester.pump();
    await io(tester);
  }

  Finder switchOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(OatsSwitch),
  );

  bool switchValue(WidgetTester tester, String label) =>
      tester.widget<OatsSwitch>(switchOf(label)).value;

  Future<void> toggle(WidgetTester tester, String label) async {
    await tester.ensureVisible(switchOf(label));
    await tester.tap(switchOf(label));
    await tester.pump();
    await io(tester);
  }

  void writePrefs(Map<String, Object?> prefs) {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(jsonEncode(prefs));
  }

  testWidgets('la section « Agenda et réunions » est là', (
    WidgetTester tester,
  ) async {
    FakeCalendarPlatform().install();
    FakeMeetingPlatform().install();

    await open(tester);

    expect(find.text('settings.calendar.title'.tr()), findsOneWidget);
  });

  group('connexion', () {
    testWidgets('non connecté : « Connecter », aucun agenda lu', (
      WidgetTester tester,
    ) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
      )..install();
      FakeMeetingPlatform().install();

      await open(tester);

      expect(find.text('settings.calendar.connect'.tr()), findsOneWidget);
      expect(find.text('Travail'), findsNothing);
      expect(platform.dataReads, isEmpty);
    });

    testWidgets('« Connecter » accordé : liste des agendas, « Déconnecter », '
        'choix rangé', (WidgetTester tester) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform()..install();
      FakeMeetingPlatform().install();
      await open(tester);

      await tapText(tester, 'settings.calendar.connect'.tr());

      expect(platform.callsTo('requestAccess'), hasLength(1));
      expect(find.text('Travail'), findsOneWidget);
      expect(find.text('Perso'), findsOneWidget);
      expect(find.text('settings.calendar.disconnect'.tr()), findsOneWidget);
      expect(readPrefs()['calendar_connected'], isTrue);
    });

    testWidgets('« Connecter » refusé : la marche à suivre et le bouton '
        'vers Réglages Système', (WidgetTester tester) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        afterRequest: 'denied',
      )..install();
      FakeMeetingPlatform().install();
      await open(tester);

      await tapText(tester, 'settings.calendar.connect'.tr());

      expect(
        find.textContaining('settings.calendar.denied'.tr()),
        findsOneWidget,
      );
      await tapText(tester, 'settings.calendar.open_settings'.tr());
      expect(platform.callsTo('openPrivacySettings'), hasLength(1));
    });

    testWidgets('« Déconnecter » : choix rangé, plus rien n\'est lu, '
        '« Connecter » revient', (WidgetTester tester) async {
      writePrefs(<String, Object?>{'calendar_connected': true});
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
      )..install();
      FakeMeetingPlatform().install();
      await open(tester);

      await tapText(tester, 'settings.calendar.disconnect'.tr());
      final int reads = platform.dataReads.length;

      expect(readPrefs()['calendar_connected'], isFalse);
      expect(find.text('settings.calendar.connect'.tr()), findsOneWidget);
      expect(find.text('Perso'), findsNothing);

      await open(tester);
      expect(platform.dataReads, hasLength(reads));
      expect(find.text('settings.calendar.connect'.tr()), findsOneWidget);
    });
  });

  group('agendas inclus', () {
    testWidgets('par défaut, tous les agendas sont inclus', (
      WidgetTester tester,
    ) async {
      writePrefs(<String, Object?>{'calendar_connected': true});
      FakeCalendarPlatform(status: 'fullAccess').install();
      FakeMeetingPlatform().install();

      await open(tester);

      expect(switchValue(tester, 'Travail'), isTrue);
      expect(switchValue(tester, 'Perso'), isTrue);
      expect(readPrefs().containsKey('calendar_ids'), isFalse);
    });

    testWidgets('exclure « Perso » : rangé et retrouvé au redémarrage', (
      WidgetTester tester,
    ) async {
      writePrefs(<String, Object?>{'calendar_connected': true});
      FakeCalendarPlatform(status: 'fullAccess').install();
      FakeMeetingPlatform().install();
      await open(tester);

      await toggle(tester, 'Perso');

      expect(readPrefs()['calendar_ids'], <String>['work']);
      await open(tester);
      expect(switchValue(tester, 'Perso'), isFalse);
      expect(switchValue(tester, 'Travail'), isTrue);
    });

    testWidgets('tout recocher retire la liste (un agenda ajouté plus tard '
        'sera inclus)', (WidgetTester tester) async {
      writePrefs(<String, Object?>{
        'calendar_connected': true,
        'calendar_ids': <String>['work'],
      });
      FakeCalendarPlatform(status: 'fullAccess').install();
      FakeMeetingPlatform().install();
      await open(tester);

      await toggle(tester, 'Perso');

      expect(readPrefs().containsKey('calendar_ids'), isFalse);
    });
  });

  group('détection des réunions', () {
    testWidgets('activée par défaut ; coupée : rangé et retrouvé', (
      WidgetTester tester,
    ) async {
      FakeCalendarPlatform().install();
      FakeMeetingPlatform().install();
      await open(tester);
      final String label = 'settings.calendar.detection'.tr();

      expect(switchValue(tester, label), isTrue);
      await toggle(tester, label);

      expect(readPrefs()['meeting_detection_enabled'], isFalse);
      await open(tester);
      expect(switchValue(tester, label), isFalse);
    });

    testWidgets('« démarrer automatiquement » : coupé par défaut (demander) ; '
        'activé : rangé et retrouvé', (WidgetTester tester) async {
      FakeCalendarPlatform().install();
      FakeMeetingPlatform().install();
      await open(tester);
      final String label = 'settings.calendar.auto_start'.tr();

      expect(switchValue(tester, label), isFalse);
      await toggle(tester, label);

      expect(readPrefs()['meeting_detection_mode'], 'auto');
      await open(tester);
      expect(switchValue(tester, label), isTrue);
    });

    testWidgets('macOS < 14 : la section dit que seuls les événements de '
        'l\'agenda sont détectés', (WidgetTester tester) async {
      FakeCalendarPlatform().install();
      FakeMeetingPlatform(supported: false).install();

      await open(tester);

      expect(
        find.textContaining('settings.calendar.mic_unsupported'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('macOS 14+ : pas de note de compatibilité', (
      WidgetTester tester,
    ) async {
      FakeCalendarPlatform().install();
      FakeMeetingPlatform().install();

      await open(tester);

      expect(
        find.textContaining('settings.calendar.mic_unsupported'.tr()),
        findsNothing,
      );
    });
  });
}
