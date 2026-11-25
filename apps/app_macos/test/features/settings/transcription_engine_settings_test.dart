import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Réglage « Moteur de transcription : Sur ce Mac / Mistral (en ligne) ».
///
/// Repères supposés :
/// - la ligne du réglage : `ValueKey<String>('stt-engine')`, avec un
///   `DropdownButton<TranscriptionEngine>` (comme le micro), entrées
///   « Sur ce Mac » et « Mistral (en ligne) » ;
/// - la raison d'un refus : `ValueKey<String>('stt-engine-refusal')` (texte
///   non vide) ;
/// - la clé Mistral se range dans le bloc `llm-mistral` (champ « Clé API »,
///   bouton « Enregistrer »), comme les autres clés ; une seule clé
///   Mistral (trousseau, compte `mistral`) ;
/// - l'interrupteur d'envoi en ligne est celui de l'IA ;
/// - la ligne rappelle de couper l'entraînement dans admin.mistral.ai ›
///   Privacy (« Data usage for improving our services ») ;
/// - prefs.json : `transcription_engine` = `local` | `mistral`.
const String _mistralKey = 'mistral-test-SECRET-0123456789';

/// Libellés des deux choix, lus dans fr.json (marqués ⟦…⟧ par
/// localized_app.dart) : un libellé écrit en dur ne correspond à rien.
String _local() => 'settings.audio.engine_local'.tr();
String _mistral() => 'settings.audio.engine_mistral'.tr();

void main() {
  late InMemoryApiKeyStore store;

  setUp(() {
    resetPrefs();
    store = InMemoryApiKeyStore();
  });

  List<Override> overrides() => <Override>[
    apiKeyStoreProvider.overrideWithValue(store),
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
  ];

  Future<void> io(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      const SettingsScreen(),
      overrides: overrides(),
      size: const Size(1280, 4000),
      settle: false,
    );
    for (int i = 0; i < 40; i++) {
      if (find.text(appDataDirectory()).evaluate().isNotEmpty) break;
      await io(tester);
    }
    await io(tester);
  }

  Finder row() => find.byKey(const ValueKey<String>('stt-engine'));
  Finder menu() => find.descendant(
    of: row(),
    matching: find.byType(DropdownButton<TranscriptionEngine>),
  );
  Finder refusal() => find.byKey(const ValueKey<String>('stt-engine-refusal'));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(menu());
    await tester.tap(menu());
    await tester.pump();
    await io(tester);
    await tester.tap(find.text(label).last);
    await tester.pump();
    await io(tester);
  }

  Future<void> allowCloud(WidgetTester tester) async {
    final Finder sw = find.descendant(
      of: find
          .ancestor(
            of: find.text('settings.ai.cloud_allowed'.tr()),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(OatsSwitch),
    );
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    await io(tester);
  }

  Future<void> saveMistralKey(WidgetTester tester) async {
    final Finder block = find.byKey(const ValueKey<String>('llm-mistral'));
    final Finder field = find.descendant(
      of: block,
      matching: find.widgetWithText(
        TextField,
        'settings.ai.api_key_label'.tr(),
      ),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, _mistralKey);
    final Finder save = find.descendant(
      of: block,
      matching: find.text('settings.ai.save'.tr()),
    );
    await tester.tap(save);
    await tester.pump();
    await io(tester);
  }

  testWidgets('par défaut : Sur ce Mac, les deux choix proposés', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(row(), findsOneWidget);
    expect(
      find.descendant(of: row(), matching: find.text(_local())),
      findsOneWidget,
    );
    await tester.ensureVisible(menu());
    await tester.tap(menu());
    await tester.pump();
    await io(tester);
    expect(find.text(_mistral()), findsWidgets);
  });

  testWidgets('Mistral sans envoi en ligne permis : refusé, raison visible, '
      'le moteur reste sur ce Mac', (WidgetTester tester) async {
    await store.write(LlmProviderId.mistral, _mistralKey);
    await open(tester);
    await choose(tester, _mistral());
    expect(refusal(), findsOneWidget);
    // prefs.json absent : rien n'a été rangé, c'est attendu.
    final Object? stored = prefsFile.existsSync()
        ? readPrefs()[TranscriptionEngineSettings.engineKey]
        : null;
    expect(stored, isNot('mistral'), reason: 'le choix refusé n est pas rangé');
    expect(
      tester.widget<DropdownButton<TranscriptionEngine>>(menu()).value,
      TranscriptionEngine.local,
      reason: 'le menu reste sur ce Mac',
    );
  });

  testWidgets('Mistral sans clé : refusé, raison visible', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await allowCloud(tester);
    await choose(tester, _mistral());
    expect(refusal(), findsOneWidget);
  });

  testWidgets('envoi permis et clé rangée : Mistral choisi et rangé, la clé '
      'n apparaît pas', (WidgetTester tester) async {
    await open(tester);
    await allowCloud(tester);
    await saveMistralKey(tester);
    await choose(tester, _mistral());
    expect(refusal(), findsNothing);
    expect(readPrefs()[TranscriptionEngineSettings.engineKey], 'mistral');
    expect(await store.read(LlmProviderId.mistral), _mistralKey);
    for (final EditableText e in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(e.controller.text, isNot(contains(_mistralKey)));
    }
  });

  testWidgets('la ligne rappelle de couper l entraînement chez Mistral', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final Iterable<String> texts = tester
        .widgetList<Text>(
          find.descendant(of: row(), matching: find.byType(Text)),
        )
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '');
    final String all = texts.join(' ');
    expect(all, contains('admin.mistral.ai'));
    expect(all, contains('Data usage for improving our services'));
  });
}
