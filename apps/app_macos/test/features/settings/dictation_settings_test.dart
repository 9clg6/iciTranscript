import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
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

/// Section « Dictée » de Réglages (T2), bâtie comme la section IA : titre de
/// section, lignes libellé + commande (`OatsSwitch`, `DropdownButton`).
/// Vrai SettingsViewModel pour la page et vrai `DictationSettingsViewModel`
/// pour la section (un view model à part, choix de l'implémenteur), vrai
/// prefs.json (dossier temporaire des tests) lu et écrit par le `PrefsStore`
/// partagé (clés `dictation_*`, voir dictation_preferences_test).
///
/// Repères supposés (en plus des textes de fr.json) :
/// - la section porte `ValueKey<String>('settings-dictation')` ;
/// - titre `settings.dictation.title` ; interrupteur sur la ligne
///   `settings.dictation.enabled` ; raccourci affiché « ⌃⌥Espace » sur la
///   ligne `settings.dictation.shortcut` ;
/// - sortie : `DropdownButton<DictationOutputMode>`, entrées
///   `settings.dictation.output_paste` et `settings.dictation.output_clipboard` ;
/// - raccourci refusé : `settings.dictation.shortcut_unavailable`, lu de
///   `dictationShortcutStatusProvider` (`@riverpod Stream<ShortcutStatus>`) ;
/// - « Modifier » (`OatsButton` `settings.dictation.shortcut_change`) :
///   inactif tant que la dictée est coupée ;
/// - raccourci affiché avec les caractères de la disposition de clavier
///   courante (pas la position QWERTY) : modificateurs ⌃⌥⇧⌘ dans l'ordre
///   d'Apple, puis le caractère rendu par
///   `GlobalShortcutChannel.keyLabel(keyCode)` (`globalShortcutChannelProvider`) ;
///   Espace reste le mot traduit.
void main() {
  late FakeGlobalShortcutChannel shortcuts;

  setUp(() {
    resetPrefs();
    shortcuts = FakeGlobalShortcutChannel();
  });

  List<Override> overrides(ShortcutStatus status) => <Override>[
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
      (Ref ref) => Stream<ShortcutStatus>.value(status),
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
  Future<void> open(
    WidgetTester tester, {
    ShortcutStatus status = ShortcutStatus.registered,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLocalized(
      tester,
      const SettingsScreen(),
      overrides: overrides(status),
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
  Finder enabledSwitch() => find.descendant(
    of: find
        .ancestor(
          of: find.text('settings.dictation.enabled'.tr()),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(OatsSwitch),
  );
  Finder outputMenu() =>
      inSection(find.byType(DropdownButton<DictationOutputMode>));

  testWidgets('section Dictée : titre, interrupteur, raccourci, sortie', (
    WidgetTester tester,
  ) async {
    await open(tester);

    for (final String key in <String>[
      'settings.dictation.title',
      'settings.dictation.enabled',
      'settings.dictation.shortcut',
      'settings.dictation.output_paste',
      'settings.dictation.output_clipboard',
      'settings.dictation.shortcut_unavailable',
    ]) {
      expect(frValue(key), isA<String>(), reason: '$key dans fr.json');
    }
    expect(section, findsOneWidget);
    expect(
      inSection(find.text('settings.dictation.title'.tr())),
      findsOneWidget,
    );
    expect(enabledSwitch(), findsOneWidget);
    expect(outputMenu(), findsOneWidget);
  });

  testWidgets('par défaut : activée, ⌃⌥Espace, collage', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(tester.widget<OatsSwitch>(enabledSwitch()).value, isTrue);
    expect(inSection(find.textContaining('⌃⌥Espace')), findsOneWidget);
    expect(
      tester.widget<DropdownButton<DictationOutputMode>>(outputMenu()).value,
      DictationOutputMode.paste,
    );
  });

  testWidgets('désactiver la dictée : écrit dans prefs.json, gardé au '
      'redémarrage', (WidgetTester tester) async {
    await open(tester);
    await tester.ensureVisible(enabledSwitch());
    await tester.tap(enabledSwitch());
    await tester.pump();
    await io(tester);

    expect(readPrefs(), containsPair('dictation_enabled', false));
    await open(tester);
    expect(tester.widget<OatsSwitch>(enabledSwitch()).value, isFalse);
  });

  testWidgets('choisir le presse-papiers : écrit dans prefs.json, gardé au '
      'redémarrage', (WidgetTester tester) async {
    await open(tester);
    await tester.ensureVisible(outputMenu());
    await tester.tap(outputMenu());
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('settings.dictation.output_clipboard'.tr()).last,
    );
    await tester.pumpAndSettle();
    await io(tester);

    expect(readPrefs(), containsPair('dictation_output_mode', 'clipboard'));
    await open(tester);
    expect(
      tester.widget<DropdownButton<DictationOutputMode>>(outputMenu()).value,
      DictationOutputMode.clipboard,
    );
  });

  testWidgets('les autres réglages de prefs.json sont gardés', (
    WidgetTester tester,
  ) async {
    await DictationPreferences().save(const DictationSettings());
    prefsFile.writeAsStringSync(
      prefsFile.readAsStringSync().replaceFirst(
        '{',
        '{"selected_mic_id":"mic-2",',
      ),
    );
    await open(tester);
    await tester.ensureVisible(enabledSwitch());
    await tester.tap(enabledSwitch());
    await tester.pump();
    await io(tester);

    expect(readPrefs(), containsPair('selected_mic_id', 'mic-2'));
  });

  testWidgets('raccourci déjà pris : message d erreur dans la section', (
    WidgetTester tester,
  ) async {
    await open(tester, status: ShortcutStatus.unavailable);

    expect(
      inSection(find.text('settings.dictation.shortcut_unavailable'.tr())),
      findsOneWidget,
    );
  });

  testWidgets('raccourci enregistré : pas de message d erreur', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(
      find.text('settings.dictation.shortcut_unavailable'.tr()),
      findsNothing,
    );
  });

  OatsButton changeButton(WidgetTester tester) => tester.widget<OatsButton>(
    inSection(
      find.widgetWithText(
        OatsButton,
        'settings.dictation.shortcut_change'.tr(),
      ),
    ),
  );

  testWidgets('« Modifier » inactif tant que la dictée est coupée', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(changeButton(tester).onPressed, isNotNull);

    await tester.ensureVisible(enabledSwitch());
    await tester.tap(enabledSwitch());
    await tester.pump();
    await io(tester);

    expect(changeButton(tester).onPressed, isNull);
  });

  testWidgets('raccourci affiché selon la disposition de clavier courante, '
      'modificateurs dans l ordre ⌃⌥⇧⌘', (WidgetTester tester) async {
    // Touche 13 : W en QWERTY, Z en AZERTY.
    await DictationPreferences().save(
      const DictationSettings(
        shortcut: DictationShortcut(
          keyCode: 13,
          modifiers: 256 | 512 | 2048 | 4096,
        ),
      ),
    );
    shortcuts.keyLabels[13] = 'Z';

    await open(tester);

    expect(inSection(find.text('⌃⌥⇧⌘Z')), findsOneWidget);
    expect(find.textContaining('W'), findsNothing);
  });
}
