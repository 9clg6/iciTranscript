import 'package:core_data/database/app_database.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
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
import '../../helpers/llm_fakes.dart' show writeLlmPrefs;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Réglages › Enregistrement : « Coach en direct » à côté de « Coach
/// anglais » (après l'appel).
///
/// Besoin : interrupteur coupé par défaut ; disponible seulement avec un
/// fournisseur en ligne configuré ET autorisé ; sinon désactivé, avec la
/// raison (le modèle local ralentirait la transcription : rien n'est envoyé
/// pendant la réunion). Persistance au redémarrage : épinglée par
/// test/features/live_transcription/live_coach_wiring_test.dart (vrai view
/// model).
///
/// Repères supposés : libellé `coach.live.option`, description
/// `coach.live.description`, raison `coach.live.unavailable` ; un
/// `OatsSwitch` sur la même `Row` que le libellé (comme les autres lignes).
void main() {
  late AppDatabase db;

  setUp(resetPrefs);
  tearDown(resetPrefs);

  List<Override> overrides(WidgetTester tester) => <Override>[
    ...localModelOverrides(db, InstantOllamaService(installed: true)),
    apiKeyStoreProvider.overrideWithValue(
      InMemoryApiKeyStore(<LlmProviderId, String>{
        LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
      }),
    ),
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

  Future<void> open(WidgetTester tester, {required bool cloud}) async {
    FakeCalendarPlatform().install();
    FakeMeetingPlatform().install();
    await tester.runAsync(
      () => writeLlmPrefs(
        cloudAllowed: cloud,
        preferred: LlmProviderId.anthropic,
      ),
    );
    db = memoryDatabase();
    addTearDown(db.close);
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

  String label() => 'coach.live.option'.tr();

  Finder switchOf(String text) => find.descendant(
    of: find.ancestor(of: find.text(text), matching: find.byType(Row)).first,
    matching: find.byType(OatsSwitch),
  );

  OatsSwitch liveSwitch(WidgetTester tester) =>
      tester.widget<OatsSwitch>(switchOf('coach.live.option'.tr()));

  testWidgets('Claude configuré et autorisé : la ligne est là, coupée par '
      'défaut, et s\'active', (WidgetTester tester) async {
    await open(tester, cloud: true);

    expect(find.text(label()), findsOneWidget);
    expect(find.text('coach.live.description'.tr()), findsOneWidget);
    expect(liveSwitch(tester).value, isFalse);
    expect(liveSwitch(tester).onChanged, isNotNull);

    await tester.ensureVisible(switchOf(label()));
    await tester.tap(switchOf(label()));
    await tester.pump();
    await io(tester);

    expect(liveSwitch(tester).value, isTrue);
  });

  testWidgets('envoi coupé (clé présente, modèle local installé) : '
      'désactivé, la raison est dite', (WidgetTester tester) async {
    await open(tester, cloud: false);

    expect(find.text(label()), findsOneWidget);
    expect(liveSwitch(tester).onChanged, isNull);
    expect(find.text('coach.live.unavailable'.tr()), findsOneWidget);
  });

  testWidgets('« Coach anglais » (après l\'appel) reste là et garde son sens', (
    WidgetTester tester,
  ) async {
    await open(tester, cloud: false);

    expect(find.text('settings.recording.coach'.tr()), findsOneWidget);
    expect(
      tester
          .widget<OatsSwitch>(switchOf('settings.recording.coach'.tr()))
          .onChanged,
      isNotNull,
      reason: 'le coach d\'après l\'appel marche aussi avec le modèle local',
    );
  });
}
