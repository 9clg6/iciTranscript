import 'package:core_presentation/core_presentation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Section IA de la page Réglages (besoins 1, 2, 3, 6, 9) : clés API,
/// bouton Tester, fournisseur actif, modèle, envoi à un service en ligne.
///
/// Repères supposés (en plus des textes de fr.json) :
/// - un bloc par fournisseur, `ValueKey<String>('llm-<LlmProviderId.name>')`
///   (anthropic, openai, gemini, ollama) ; chaque bloc affiche le nom du
///   fournisseur et contient ses champs, boutons et résultats de test ;
/// - champ de clé : `TextField` de `labelText` `settings.ai.api_key_label`
///   (pas de champ de clé pour Ollama) ; champ de modèle : `TextField` de
///   `labelText` `settings.ai.model_label`, valeur ou indication = modèle
///   par défaut ;
/// - fournisseur actif : `DropdownButton<LlmProviderId>` (comme le micro) ;
/// - interrupteur « Autoriser l'envoi… » : `OatsSwitch` sur la même ligne que
///   son libellé (comme les autres réglages).
///
/// Vrai SettingsViewModel, vrai prefs.json (dossier temporaire des tests),
/// trousseau en mémoire, transport HTTP factice.
const String _claudeKey = 'sk-ant-test-SECRET-0123456789';
const String _openAiKey = 'sk-openai-test-SECRET-9876543210';
const String _geminiKey = 'AIza-test-SECRET-5555544444';

const Map<LlmProviderId, String> _keys = <LlmProviderId, String>{
  LlmProviderId.anthropic: _claudeKey,
  LlmProviderId.openai: _openAiKey,
  LlmProviderId.gemini: _geminiKey,
};

const List<LlmProviderId> _cloud = <LlmProviderId>[
  LlmProviderId.anthropic,
  LlmProviderId.openai,
  LlmProviderId.gemini,
];

const Map<LlmProviderId, String> _defaultModel = <LlmProviderId, String>{
  LlmProviderId.anthropic: 'claude-haiku-5-5',
  LlmProviderId.openai: 'gpt-6-luna',
  LlmProviderId.gemini: 'gemini-3.5-flash-lite',
  LlmProviderId.ollama: 'mistral',
};

String _last4(String key) => key.substring(key.length - 4);

void main() {
  late InMemoryApiKeyStore store;
  late RecordingHttpAdapter adapter;

  setUp(() {
    resetPrefs();
    store = InMemoryApiKeyStore();
    adapter = RecordingHttpAdapter();
  });

  List<Override> overrides() => <Override>[
    apiKeyStoreProvider.overrideWithValue(store),
    llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
    liveTranscriptionViewModelProvider.overrideWith(
      FakeLiveTranscriptionViewModel.new,
    ),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
  ];

  /// Laisse passer les vraies lectures/écritures de fichier (prefs.json),
  /// puis quelques images.
  Future<void> io(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Ouvre la page Réglages ; appelé deux fois dans un test = redémarrage
  /// (nouveau ProviderScope, mêmes trousseau et prefs.json).
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLocalized(
      tester,
      const SettingsScreen(),
      overrides: overrides(),
      size: const Size(1280, 4000),
      settle: false,
    );
    await io(tester);
  }

  Finder block(LlmProviderId id) =>
      find.byKey(ValueKey<String>('llm-${id.name}'));
  Finder inBlock(LlmProviderId id, Finder f) =>
      find.descendant(of: block(id), matching: f);
  Finder textIn(LlmProviderId id, String key, {List<String>? args}) =>
      inBlock(id, find.text(key.tr(args: args)));
  Finder keyField(LlmProviderId id) => inBlock(
    id,
    find.widgetWithText(TextField, 'settings.ai.api_key_label'.tr()),
  );
  Finder modelField(LlmProviderId id) => inBlock(
    id,
    find.widgetWithText(TextField, 'settings.ai.model_label'.tr()),
  );
  Finder masked(LlmProviderId id, String key) =>
      textIn(id, 'settings.ai.key_saved', args: <String>[_last4(key)]);

  Finder cloudSwitch() => find.descendant(
    of: find
        .ancestor(
          of: find.text('settings.ai.cloud_allowed'.tr()),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(OatsSwitch),
  );

  Finder providerMenu() => find.byType(DropdownButton<LlmProviderId>);

  Future<void> tapIn(WidgetTester tester, LlmProviderId id, String key) async {
    final Finder target = textIn(id, key);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await io(tester);
  }

  Future<void> allowCloud(WidgetTester tester) async {
    await tester.ensureVisible(cloudSwitch());
    await tester.tap(cloudSwitch());
    await tester.pump();
    await io(tester);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

  /// La clé n'apparaît nulle part en clair : ni texte, ni champ.
  void expectKeyNowhere(WidgetTester tester, String key) {
    for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
      expect(
        t.data ?? t.textSpan?.toPlainText() ?? '',
        isNot(contains(key)),
      );
    }
    for (final RichText t in tester.widgetList<RichText>(
      find.byType(RichText),
    )) {
      expect(t.text.toPlainText(), isNot(contains(key)));
    }
    for (final EditableText e in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(e.controller.text, isNot(contains(key)));
    }
  }

  group('structure de la section', () {
    testWidgets('titre de section, un bloc par fournisseur avec son nom, '
        'clé pour les fournisseurs en ligne seulement', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('settings.ai.title'.tr()), findsOneWidget);
      for (final LlmProviderId id in LlmProviderId.values) {
        expect(block(id), findsOneWidget, reason: id.name);
        expect(
          textIn(id, 'settings.ai.provider.${id.name}'),
          findsWidgets,
          reason: id.name,
        );
      }
      for (final LlmProviderId id in _cloud) {
        expect(keyField(id), findsOneWidget, reason: id.name);
      }
      expect(keyField(LlmProviderId.ollama), findsNothing);
    });

    testWidgets('chaque fournisseur montre son modèle par défaut', (
      WidgetTester tester,
    ) async {
      await open(tester);

      for (final LlmProviderId id in LlmProviderId.values) {
        expect(modelField(id), findsOneWidget, reason: id.name);
        expect(
          inBlock(id, find.text(_defaultModel[id]!)),
          findsWidgets,
          reason: '${id.name} : ${_defaultModel[id]}',
        );
      }
    });

    testWidgets('confidentialité : interrupteur coupé par défaut et phrase '
        'qui dit ce qui part', (WidgetTester tester) async {
      await open(tester);

      expect(find.text('settings.ai.cloud_allowed'.tr()), findsOneWidget);
      expect(find.text('settings.ai.privacy_notice'.tr()), findsOneWidget);
      expect(tester.widget<OatsSwitch>(cloudSwitch()).value, isFalse);
    });
  });

  group('clé API', () {
    testWidgets('enregistrer : rangée au trousseau, puis masquée (4 derniers '
        'caractères) avec Remplacer et Supprimer', (WidgetTester tester) async {
      await open(tester);

      await tester.enterText(keyField(LlmProviderId.anthropic), _claudeKey);
      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.save');

      expect(store.keys[LlmProviderId.anthropic], _claudeKey);
      expect(masked(LlmProviderId.anthropic, _claudeKey), findsOneWidget);
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.replace'),
        findsOneWidget,
      );
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.remove'),
        findsOneWidget,
      );
      expectKeyNowhere(tester, _claudeKey);
    });

    testWidgets('au clavier seul : Entrée dans le champ enregistre', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.enterText(keyField(LlmProviderId.openai), _openAiKey);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await io(tester);

      expect(store.keys[LlmProviderId.openai], _openAiKey);
      expect(masked(LlmProviderId.openai, _openAiKey), findsOneWidget);
    });

    testWidgets('saisie vide : Enregistrer ne fait rien', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.enterText(keyField(LlmProviderId.gemini), '   ');
      await tapIn(tester, LlmProviderId.gemini, 'settings.ai.save');

      expect(store.writeCalls, 0);
      expect(store.deleteCalls, 0);
      expect(store.keys, isEmpty);
      expect(textIn(LlmProviderId.gemini, 'settings.ai.remove'), findsNothing);
    });

    testWidgets('clé déjà rangée à l\'ouverture (redémarrage) : masquée, '
        'jamais en clair', (WidgetTester tester) async {
      store.keys.addAll(_keys);
      await open(tester);

      for (final LlmProviderId id in _cloud) {
        expect(masked(id, _keys[id]!), findsOneWidget, reason: id.name);
        expectKeyNowhere(tester, _keys[id]!);
      }
    });

    testWidgets('remplacer : la nouvelle clé est rangée et masquée', (
      WidgetTester tester,
    ) async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      await open(tester);

      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.replace');
      await tester.enterText(
        keyField(LlmProviderId.anthropic),
        'sk-ant-NEW-KEY-4242',
      );
      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.save');

      expect(store.keys[LlmProviderId.anthropic], 'sk-ant-NEW-KEY-4242');
      expect(
        textIn(
          LlmProviderId.anthropic,
          'settings.ai.key_saved',
          args: <String>['4242'],
        ),
        findsOneWidget,
      );
      expectKeyNowhere(tester, 'sk-ant-NEW-KEY-4242');
    });

    testWidgets('remplacer puis enregistrer à vide : l\'ancienne clé reste', (
      WidgetTester tester,
    ) async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      await open(tester);

      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.replace');
      await tester.enterText(keyField(LlmProviderId.anthropic), '');
      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.save');

      expect(store.keys[LlmProviderId.anthropic], _claudeKey);
      expect(store.writeCalls, 0);
      expect(store.deleteCalls, 0);
    });

    testWidgets('supprimer : retirée du trousseau, le champ revient vide', (
      WidgetTester tester,
    ) async {
      store.keys[LlmProviderId.openai] = _openAiKey;
      await open(tester);

      await tapIn(tester, LlmProviderId.openai, 'settings.ai.remove');

      expect(store.keys, isEmpty);
      expect(masked(LlmProviderId.openai, _openAiKey), findsNothing);
      expect(keyField(LlmProviderId.openai), findsOneWidget);
      final EditableText field = tester.widget<EditableText>(
        find.descendant(
          of: keyField(LlmProviderId.openai),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, isEmpty);
    });

    testWidgets('le trousseau refuse l\'enregistrement : message d\'erreur, '
        'pas de clé masquée, rien en clair hors du champ', (
      WidgetTester tester,
    ) async {
      store.refuseWrites = true;
      await open(tester);

      await tester.enterText(keyField(LlmProviderId.anthropic), _claudeKey);
      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.save');

      expect(tester.takeException(), isNull);
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.key_error'),
        findsOneWidget,
      );
      expect(masked(LlmProviderId.anthropic, _claudeKey), findsNothing);
      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? '', isNot(contains(_claudeKey)));
      }
    });

    testWidgets('le trousseau refuse la lecture à l\'ouverture : la page '
        's\'affiche, l\'erreur est dite', (WidgetTester tester) async {
      store
        ..keys[LlmProviderId.anthropic] = _claudeKey
        ..refuseReads = true;
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('settings.ai.title'.tr()), findsOneWidget);
      expect(find.text('settings.ai.key_error'.tr()), findsWidgets);
      expectKeyNowhere(tester, _claudeKey);
    });
  });

  group('Tester', () {
    for (final LlmProviderId id in _cloud) {
      testWidgets('${id.name} : requête envoyée avec la clé rangée, '
          '« connexion réussie »', (WidgetTester tester) async {
        store.keys[id] = _keys[id]!;
        adapter.reply = BodyReply(200, kOkStream[id]!);
        await open(tester);
        await allowCloud(tester);

        await tapIn(tester, id, 'settings.ai.test');

        expect(adapter.lastHost, kProviderHost[id]);
        expect(
          adapter.requests.last.headers.values.join(' '),
          contains(_keys[id]!),
        );
        expect(textIn(id, 'settings.ai.test_ok'), findsOneWidget);
        expectKeyNowhere(tester, _keys[id]!);
      });
    }

    const Map<String, FakeReply> failures = <String, FakeReply>{
      'settings.ai.test_invalid_key': BodyReply(
        401,
        '{"error": "invalid x-api-key sk-ant-test-SECRET-0123456789"}',
      ),
      'settings.ai.test_rate_limited': BodyReply(429, '{"error": "rate"}'),
      'settings.ai.test_unreachable': UnreachableReply(),
      'settings.ai.test_failed': BodyReply(500, '{"error": "overloaded"}'),
    };
    failures.forEach((String message, FakeReply reply) {
      testWidgets('échec ($message) : le message dit lequel, sans la clé, '
          'pas de succès', (WidgetTester tester) async {
        store.keys[LlmProviderId.anthropic] = _claudeKey;
        adapter.reply = reply;
        await open(tester);
        await allowCloud(tester);

        await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.test');

        expect(textIn(LlmProviderId.anthropic, message), findsOneWidget);
        expect(
          textIn(LlmProviderId.anthropic, 'settings.ai.test_ok'),
          findsNothing,
        );
        expectKeyNowhere(tester, _claudeKey);
      });
    });

    testWidgets('Gemini 403 : « clé invalide »', (WidgetTester tester) async {
      store.keys[LlmProviderId.gemini] = _geminiKey;
      adapter.reply = const BodyReply(403, '{"error": {"code": 403}}');
      await open(tester);
      await allowCloud(tester);

      await tapIn(tester, LlmProviderId.gemini, 'settings.ai.test');

      expect(
        textIn(LlmProviderId.gemini, 'settings.ai.test_invalid_key'),
        findsOneWidget,
      );
    });

    testWidgets('pas de réponse : « test en cours », puis « injoignable » '
        'une fois le délai passé', (WidgetTester tester) async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      adapter.reply = const HangReply();
      await open(tester);
      await allowCloud(tester);

      await tapIn(tester, LlmProviderId.anthropic, 'settings.ai.test');
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.testing'),
        findsOneWidget,
      );

      await tester.pump(kLlmConnectTimeout + kLlmIdleTimeout);
      await tester.pump(const Duration(seconds: 1));

      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.test_unreachable'),
        findsOneWidget,
      );
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.testing'),
        findsNothing,
      );
    });

    testWidgets('envoi en ligne non autorisé : Tester n\'envoie rien', (
      WidgetTester tester,
    ) async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      adapter.reply = BodyReply(200, kOkStream[LlmProviderId.anthropic]!);
      await open(tester);

      final Finder test = textIn(LlmProviderId.anthropic, 'settings.ai.test');
      if (test.evaluate().isNotEmpty) {
        await tester.ensureVisible(test);
        await tester.tap(test, warnIfMissed: false);
        await tester.pump();
        await io(tester);
      }

      expect(adapter.requests, isEmpty);
      expect(
        textIn(LlmProviderId.anthropic, 'settings.ai.test_ok'),
        findsNothing,
      );
    });

    testWidgets('sans clé rangée : Tester n\'envoie rien', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await allowCloud(tester);

      final Finder test = textIn(LlmProviderId.openai, 'settings.ai.test');
      if (test.evaluate().isNotEmpty) {
        await tester.ensureVisible(test);
        await tester.tap(test, warnIfMissed: false);
        await tester.pump();
        await io(tester);
      }

      expect(adapter.requests, isEmpty);
    });
  });

  group('fournisseur actif', () {
    Set<LlmProviderId?> offered(WidgetTester tester, {bool enabledOnly = true}) =>
        <LlmProviderId?>{
          for (final DropdownMenuItem<LlmProviderId> item
              in tester
                      .widget<DropdownButton<LlmProviderId>>(providerMenu())
                      .items ??
                  <DropdownMenuItem<LlmProviderId>>[])
            if (!enabledOnly || item.enabled) item.value,
        };

    testWidgets('propose le modèle local et les seuls fournisseurs '
        'configurés', (WidgetTester tester) async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      await open(tester);
      await allowCloud(tester);

      expect(offered(tester), <LlmProviderId>{
        LlmProviderId.ollama,
        LlmProviderId.anthropic,
      });
    });

    testWidgets('envoi en ligne coupé : seul le modèle local est '
        'sélectionnable', (WidgetTester tester) async {
      store.keys.addAll(_keys);
      await open(tester);

      expect(offered(tester), <LlmProviderId>{LlmProviderId.ollama});
      expect(
        tester.widget<DropdownButton<LlmProviderId>>(providerMenu()).value,
        LlmProviderId.ollama,
      );
    });

    testWidgets('choisir OpenAI dans le menu : rangé dans prefs.json, la '
        'requête suivante part chez OpenAI', (WidgetTester tester) async {
      store.keys
        ..[LlmProviderId.anthropic] = _claudeKey
        ..[LlmProviderId.openai] = _openAiKey;
      await open(tester);
      await allowCloud(tester);

      await tester.ensureVisible(providerMenu());
      await tester.tap(providerMenu());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('settings.ai.provider.openai'.tr()).last);
      await tester.pump(const Duration(milliseconds: 500));
      await io(tester);

      expect(readPrefs()['llm_provider'], 'openai');
      final LlmProvider provider = await tester.runAsync(
        () => container(tester).read(activeLlmProviderProvider.future),
      ) as LlmProvider;
      await tester.runAsync(() => sendPing(provider));
      expect(adapter.lastHost, kProviderHost[LlmProviderId.openai]);
    });

    testWidgets('supprimer la clé du fournisseur choisi : le menu montre le '
        'repli', (WidgetTester tester) async {
      store.keys
        ..[LlmProviderId.anthropic] = _claudeKey
        ..[LlmProviderId.openai] = _openAiKey;
      await open(tester);
      await allowCloud(tester);
      await tester.ensureVisible(providerMenu());
      await tester.tap(providerMenu());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('settings.ai.provider.openai'.tr()).last);
      await tester.pump(const Duration(milliseconds: 500));
      await io(tester);

      await tapIn(tester, LlmProviderId.openai, 'settings.ai.remove');

      expect(offered(tester), isNot(contains(LlmProviderId.openai)));
      expect(
        tester.widget<DropdownButton<LlmProviderId>>(providerMenu()).value,
        LlmProviderId.anthropic,
      );
    });
  });

  group('persistance des réglages de la section', () {
    testWidgets('interrupteur d\'envoi activé : toujours activé à la '
        'réouverture', (WidgetTester tester) async {
      await open(tester);
      await allowCloud(tester);
      expect(tester.widget<OatsSwitch>(cloudSwitch()).value, isTrue);

      await open(tester);

      expect(tester.widget<OatsSwitch>(cloudSwitch()).value, isTrue);
    });

    testWidgets('modèle saisi puis validé : gardé à la réouverture', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.enterText(
        modelField(LlmProviderId.anthropic),
        'claude-opus-test',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await io(tester);
      expect(prefsFile.readAsStringSync(), contains('claude-opus-test'));

      await open(tester);

      final EditableText field = tester.widget<EditableText>(
        find.descendant(
          of: modelField(LlmProviderId.anthropic),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, 'claude-opus-test');
    });
  });
}
