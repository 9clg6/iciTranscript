import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Enregistreur du raccourci de dictée (Réglages › Dictée › Raccourci ›
/// « Modifier »). Rapport : l'utilisateur appuie ⌘⌥ (rien d'autre) et rien
/// ne se passe ; il voulait un raccourci « à deux touches ».
///
/// Comportement épinglé :
/// - deux modificateurs ou plus parmi ⌃ ⌥ ⇧ ⌘ (donc au moins un de ⌃ ⌥ ⌘),
///   enfoncés puis relâchés sans autre touche : raccourci « modificateurs
///   seuls » enregistré (prefs.json : `dictation_modifiers` sans
///   `dictation_key_code`, voir modifier_only_shortcut_preferences_test) ;
///   la ligne affiche ses symboles dans l'ordre d'Apple déjà épinglé
///   (⌃⌥⇧⌘) : ⌘ + ⌥ s'affiche « ⌥⌘ », quel que soit l'ordre d'appui ou de
///   relâchement ; gardé au redémarrage ;
/// - un seul modificateur (⌘ seul, ⇧ seul) : refusé, message en français
///   dans la section (`settings.dictation.shortcut_needs_two_modifiers`),
///   rien d'enregistré ; l'enregistreur reste à l'écoute pour un autre essai ;
/// - modificateurs + touche : comme aujourd'hui (⌘⌥ puis D = « ⌥⌘D »), le
///   relâchement des modificateurs qui suit ne l'écrase pas ;
/// - Échap : annule, rien d'enregistré.
///
/// Touches simulées en macOS (`platform: 'macos'`) : la table des codes de
/// touche est celle de macOS.
void main() {
  late FakeGlobalShortcutChannel shortcuts;

  setUp(() {
    resetPrefs();
    shortcuts = FakeGlobalShortcutChannel()..keyLabels[2] = 'D';
  });

  List<Override> overrides() => <Override>[
    globalShortcutChannelProvider.overrideWithValue(shortcuts),
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

  final Finder section = find.byKey(
    const ValueKey<String>('settings-dictation'),
  );
  Finder inSection(Finder f) => find.descendant(of: section, matching: f);
  Finder changeButton() => inSection(
    find.widgetWithText(OatsButton, 'settings.dictation.shortcut_change'.tr()),
  );
  Finder recording() =>
      inSection(find.text('settings.dictation.shortcut_recording'.tr()));
  Finder twoModifiersMessage() => inSection(
    find.text('settings.dictation.shortcut_needs_two_modifiers'.tr()),
  );

  Future<void> startRecording(WidgetTester tester) async {
    await tester.ensureVisible(changeButton());
    await tester.tap(changeButton());
    await tester.pump();
    expect(recording(), findsOneWidget);
  }

  Future<void> down(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key, platform: 'macos');
    await tester.pump();
  }

  Future<void> up(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyUpEvent(key, platform: 'macos');
    await tester.pump();
  }

  Map<String, dynamic> prefsOrEmpty() =>
      prefsFile.existsSync() ? readPrefs() : <String, dynamic>{};

  testWidgets('⌘⌥ puis D : raccourci à touche, comme aujourd hui', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await startRecording(tester);

    await down(tester, LogicalKeyboardKey.metaLeft);
    await down(tester, LogicalKeyboardKey.altLeft);
    await down(tester, LogicalKeyboardKey.keyD);
    await up(tester, LogicalKeyboardKey.keyD);
    await up(tester, LogicalKeyboardKey.altLeft);
    await up(tester, LogicalKeyboardKey.metaLeft);
    await io(tester);

    expect(recording(), findsNothing);
    expect(inSection(find.text('⌥⌘D')), findsOneWidget);
    expect(prefsOrEmpty(), containsPair('dictation_key_code', 2));
    expect(prefsOrEmpty(), containsPair('dictation_modifiers', 2304));
  });

  testWidgets('⌘⌥ seuls, enfoncés puis relâchés : enregistrés, affichés '
      '« ⌥⌘ », gardés au redémarrage', (WidgetTester tester) async {
    await open(tester);
    await startRecording(tester);

    await down(tester, LogicalKeyboardKey.metaLeft);
    await down(tester, LogicalKeyboardKey.altLeft);
    await up(tester, LogicalKeyboardKey.altLeft);
    await up(tester, LogicalKeyboardKey.metaLeft);
    await io(tester);

    expect(recording(), findsNothing);
    expect(inSection(find.text('⌥⌘')), findsOneWidget);
    expect(prefsOrEmpty(), containsPair('dictation_modifiers', 2304));
    expect(prefsOrEmpty().containsKey('dictation_key_code'), isFalse);

    await open(tester);
    expect(inSection(find.text('⌥⌘')), findsOneWidget);
  });

  testWidgets('⌥ puis ⌘, relâchés dans l autre ordre : même « ⌥⌘ »', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await startRecording(tester);

    await down(tester, LogicalKeyboardKey.altRight);
    await down(tester, LogicalKeyboardKey.metaRight);
    await up(tester, LogicalKeyboardKey.altRight);
    await up(tester, LogicalKeyboardKey.metaRight);
    await io(tester);

    expect(inSection(find.text('⌥⌘')), findsOneWidget);
    expect(prefsOrEmpty(), containsPair('dictation_modifiers', 2304));
  });

  testWidgets('⌥⇧ : accepté (⇧ compte s il accompagne ⌃, ⌥ ou ⌘)', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await startRecording(tester);

    await down(tester, LogicalKeyboardKey.altLeft);
    await down(tester, LogicalKeyboardKey.shiftLeft);
    await up(tester, LogicalKeyboardKey.shiftLeft);
    await up(tester, LogicalKeyboardKey.altLeft);
    await io(tester);

    expect(inSection(find.text('⌥⇧')), findsOneWidget);
    expect(prefsOrEmpty(), containsPair('dictation_modifiers', 2048 | 512));
    expect(prefsOrEmpty().containsKey('dictation_key_code'), isFalse);
  });

  for (final ({String name, LogicalKeyboardKey key}) single
      in <({String name, LogicalKeyboardKey key})>[
        (name: '⌘', key: LogicalKeyboardKey.metaLeft),
        (name: '⇧', key: LogicalKeyboardKey.shiftLeft),
      ]) {
    testWidgets('${single.name} seul : refusé avec un message en français, '
        'rien d enregistré, nouvel essai possible', (
      WidgetTester tester,
    ) async {
      expect(
        frValue('settings.dictation.shortcut_needs_two_modifiers'),
        isA<String>(),
        reason: 'message dans fr.json',
      );
      await open(tester);
      await startRecording(tester);

      await down(tester, single.key);
      await up(tester, single.key);
      await io(tester);

      expect(twoModifiersMessage(), findsOneWidget);
      expect(prefsOrEmpty().containsKey('dictation_modifiers'), isFalse);
      expect(recording(), findsOneWidget);

      // Toujours à l'écoute : ⌘⌥ est pris tout de suite.
      await down(tester, LogicalKeyboardKey.metaLeft);
      await down(tester, LogicalKeyboardKey.altLeft);
      await up(tester, LogicalKeyboardKey.altLeft);
      await up(tester, LogicalKeyboardKey.metaLeft);
      await io(tester);

      expect(twoModifiersMessage(), findsNothing);
      expect(inSection(find.text('⌥⌘')), findsOneWidget);
    });
  }

  testWidgets('Échap : enregistrement annulé, raccourci inchangé', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await startRecording(tester);

    await down(tester, LogicalKeyboardKey.escape);
    await up(tester, LogicalKeyboardKey.escape);
    await io(tester);

    expect(recording(), findsNothing);
    expect(inSection(find.textContaining('⌃⌥Espace')), findsOneWidget);
    expect(prefsOrEmpty().containsKey('dictation_modifiers'), isFalse);
  });
}
