import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';

import '../../helpers/dictation_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Revue PR #19, point 3 : dictée activée mais modèle de transcription
/// absent du cache. Réglages le dit dans la section Dictée et propose un
/// geste explicite pour le télécharger (jamais de téléchargement muet).
///
/// API supposée : `transcriptionModelCachedProvider`
/// (`@riverpod Future<bool>`, lib/core/providers/services/dictation.provider.dart),
/// textes `settings.dictation.model_missing` et
/// `settings.dictation.download_model` (`OatsButton`). Le bouton appelle
/// `DictationController.downloadModel()` (voir dictation_model_missing_test).
void main() {
  setUp(resetPrefs);

  List<Override> overrides({required bool cached}) => <Override>[
    globalShortcutChannelProvider.overrideWithValue(
      FakeGlobalShortcutChannel(),
    ),
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
    dictationShortcutStatusProvider.overrideWith(
      (Ref ref) => Stream<ShortcutStatus>.value(ShortcutStatus.registered),
    ),
    transcriptionModelCachedProvider.overrideWith((Ref ref) async => cached),
  ];

  Future<void> open(WidgetTester tester, {required bool cached}) async {
    await pumpLocalized(
      tester,
      const SettingsScreen(),
      overrides: overrides(cached: cached),
      size: const Size(1280, 4000),
      settle: false,
    );
    for (int i = 0; i < 40; i++) {
      if (find.text(appDataDirectory()).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  final Finder section = find.byKey(
    const ValueKey<String>('settings-dictation'),
  );
  Finder inSection(Finder f) => find.descendant(of: section, matching: f);
  Finder download() => inSection(
    find.widgetWithText(OatsButton, 'settings.dictation.download_model'.tr()),
  );

  testWidgets('modèle absent : message et bouton de téléchargement actif', (
    WidgetTester tester,
  ) async {
    await open(tester, cached: false);

    expect(frValue('settings.dictation.model_missing'), isA<String>());
    expect(frValue('settings.dictation.download_model'), isA<String>());
    expect(
      inSection(find.text('settings.dictation.model_missing'.tr())),
      findsOneWidget,
    );
    expect(download(), findsOneWidget);
    expect(tester.widget<OatsButton>(download()).onPressed, isNotNull);
  });

  testWidgets('modèle présent : ni message ni bouton', (
    WidgetTester tester,
  ) async {
    await open(tester, cached: true);

    expect(find.text('settings.dictation.model_missing'.tr()), findsNothing);
    expect(download(), findsNothing);
  });
}
