import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings_dictation.view_model.dart';
import 'package:rxdart/rxdart.dart';

import '../../helpers/dictation_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Raccourci « modificateurs seuls » (⌘⌥) et permission Accessibilité.
/// Surveiller les modificateurs en global demande l'Accessibilité ; sans
/// elle le plugin refuse (`registerModifiers` → faux, voir
/// global_shortcut_modifier_only_test) et la dictée le dit
/// (`ShortcutStatus.needsAccessibility`).
///
/// Comportement épinglé :
/// - raccourci modificateurs seuls refusé faute d'Accessibilité : la ligne
///   du raccourci le dit en français
///   (`settings.dictation.shortcut_needs_accessibility`), avec, à côté du
///   message, la même action que le mode collage (« Ouvrir les Réglages »,
///   `settings.dictation.accessibility_open` → volet Accessibilité des
///   Réglages Système) ; jamais le texte « déjà pris » ;
/// - permission accordée (état du raccourci qui passe à `registered`) : le
///   message disparaît ;
/// - raccourci à touche, Accessibilité absente : pas ce message (Carbon n'a
///   pas besoin de l'Accessibilité ; la ligne Accessibilité du bas reste) ;
/// - jamais muet : au retour des Réglages Système avec l'Accessibilité
///   accordée (`refreshAccessibility`, appelé à la reprise de l'app), le
///   raccourci est reposé et marche, sans le réenregistrer.
void main() {
  late FakeGlobalShortcutChannel shortcuts;
  late FakeTextOutputChannel output;
  late BehaviorSubject<ShortcutStatus> status;

  void saveModifierOnlyByHand() {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(
      jsonEncode(<String, Object>{'dictation_modifiers': 256 | 2048}),
    );
  }

  setUp(() {
    resetPrefs();
    shortcuts = FakeGlobalShortcutChannel();
    output = FakeTextOutputChannel()..trusted = false;
    status = BehaviorSubject<ShortcutStatus>.seeded(
      ShortcutStatus.needsAccessibility,
    );
    addTearDown(status.close);
  });

  List<Override> overrides() => <Override>[
    globalShortcutChannelProvider.overrideWithValue(shortcuts),
    textOutputChannelProvider.overrideWithValue(output),
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
    dictationShortcutStatusProvider.overrideWith((Ref ref) => status.stream),
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
  Finder needsAccessibility() => inSection(
    find.text('settings.dictation.shortcut_needs_accessibility'.tr()),
  );
  Finder openSettingsButton() => find.widgetWithText(
    OatsButton,
    'settings.dictation.accessibility_open'.tr(),
  );

  /// « Ouvrir les Réglages » le plus proche de [message] : dans le plus petit
  /// ancêtre commun, qui ne doit pas être la ligne Accessibilité du bas.
  Finder actionNextTo(Finder message) {
    for (final Element ancestor in find
        .ancestor(of: message, matching: find.byWidgetPredicate((_) => true))
        .evaluate()) {
      final Finder button = find.descendant(
        of: find.byElementPredicate((Element e) => e == ancestor),
        matching: openSettingsButton(),
      );
      if (button.evaluate().isEmpty) continue;
      final Finder permissionRow = find.descendant(
        of: find.byElementPredicate((Element e) => e == ancestor),
        matching: find.text('settings.dictation.accessibility'.tr()),
      );
      expect(
        permissionRow,
        findsNothing,
        reason: 'l action doit être à côté du message du raccourci',
      );
      return button.first;
    }
    fail('aucun « Ouvrir les Réglages » à côté du message');
  }

  testWidgets('⌘⌥ refusé faute d Accessibilité : la ligne le dit, avec '
      '« Ouvrir les Réglages » à côté', (WidgetTester tester) async {
    expect(
      frValue('settings.dictation.shortcut_needs_accessibility'),
      isA<String>(),
      reason: 'message dans fr.json',
    );
    saveModifierOnlyByHand();
    await open(tester);

    expect(inSection(find.text('⌥⌘')), findsOneWidget);
    expect(needsAccessibility(), findsOneWidget);
    expect(
      inSection(find.text('settings.dictation.shortcut_unavailable'.tr())),
      findsNothing,
    );

    final Finder action = actionNextTo(needsAccessibility());
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect(output.openSettingsCalls, 1);
  });

  testWidgets('permission accordée, raccourci posé : le message disparaît', (
    WidgetTester tester,
  ) async {
    saveModifierOnlyByHand();
    await open(tester);
    expect(needsAccessibility(), findsOneWidget);

    output.trusted = true;
    status.add(ShortcutStatus.registered);
    await io(tester);

    expect(needsAccessibility(), findsNothing);
  });

  testWidgets('raccourci à touche, Accessibilité absente : pas ce message', (
    WidgetTester tester,
  ) async {
    status.add(ShortcutStatus.registered);
    await open(tester);

    expect(inSection(find.textContaining('⌃⌥Espace')), findsOneWidget);
    expect(needsAccessibility(), findsNothing);
  });

  test('jamais muet : au retour des Réglages Système avec l Accessibilité '
      'accordée, ⌘⌥ est reposé sans le réenregistrer', () async {
    saveModifierOnlyByHand();
    shortcuts.registerModifiersResult = false;
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(
          AppDatabase(NativeDatabase.memory()),
        ),
        processManagerChannelProvider.overrideWithValue(
          FakeProcessManagerChannel(),
        ),
        audioCaptureChannelProvider.overrideWithValue(
          FakeAudioCaptureChannel(),
        ),
        globalShortcutChannelProvider.overrideWithValue(shortcuts),
        textOutputChannelProvider.overrideWithValue(output),
      ],
    );
    addTearDown(container.dispose);

    await container.read(kernelProvider.future);
    await eventually(() {
      expect(shortcuts.registeredModifiers, <int>[2304]);
      expect(
        container.read(dictationControllerProvider).shortcutStatus,
        ShortcutStatus.needsAccessibility,
      );
    });

    // Réglages ouverts, l'utilisateur accorde l'Accessibilité puis revient.
    container.listen(dictationSettingsViewModelProvider, (_, _) {});
    await eventually(
      () => expect(
        container
            .read(dictationSettingsViewModelProvider)
            .settings
            .shortcut
            .modifiers,
        2304,
      ),
    );
    output.trusted = true;
    shortcuts.registerModifiersResult = true;
    await container
        .read(dictationSettingsViewModelProvider.notifier)
        .refreshAccessibility();

    await eventually(() {
      expect(shortcuts.registeredModifiers, <int>[2304, 2304]);
      expect(
        container.read(dictationControllerProvider).shortcutStatus,
        ShortcutStatus.registered,
      );
    });
  });
}
