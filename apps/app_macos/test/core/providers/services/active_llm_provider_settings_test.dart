import 'dart:async';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';

import '../../../helpers/settings_fakes.dart';

/// Les choix faits dans Réglages pilotent le fournisseur LLM utilisé, tout de
/// suite et après un redémarrage (besoins 1, 3, 4, 6).
///
/// API supposée :
/// - `llmDioProvider` (core/providers/services/llm_dio.provider.dart) : le
///   Dio par lequel passent toutes les requêtes LLM ; remplacé ici par un
///   transport factice (aucun réseau).
/// - `SettingsViewModel` : `saveApiKey(id, key)`, `removeApiKey(id)`,
///   `selectLlmProvider(id)`, `updateLlmModel(id, model)`,
///   `setCloudAllowed(bool)`, tous `Future<void>`.
/// - prefs.json : `llm_provider` = `LlmProviderId.name`.
///
/// Fournisseur visé = hôte de la requête suivante, lue par
/// `activeLlmProviderProvider.future` après le changement.
const String _claudeKey = 'sk-ant-test-SECRET-0123456789';
const String _openAiKey = 'sk-openai-test-SECRET-9876543210';
const String _geminiKey = 'AIza-test-SECRET-5555544444';

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
  ];

  /// Un conteneur = un lancement de l'app. [waitForSettings] : attendre la
  /// fin du chargement des réglages avant d'agir.
  Future<ProviderContainer> launch({bool waitForSettings = true}) async {
    final ProviderContainer c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    if (waitForSettings) {
      c.read(settingsViewModelProvider);
      await eventually(
        () =>
            expect(c.read(settingsViewModelProvider).storagePath, isNotEmpty),
      );
    }
    return c;
  }

  SettingsViewModel vm(ProviderContainer c) =>
      c.read(settingsViewModelProvider.notifier);

  /// Hôte appelé par la prochaine requête.
  Future<String?> nextHost(ProviderContainer c) async {
    final LlmProvider provider = await c.read(activeLlmProviderProvider.future);
    await sendPing(provider);
    return adapter.lastHost;
  }

  final String claude = kProviderHost[LlmProviderId.anthropic]!;
  final String openAi = kProviderHost[LlmProviderId.openai]!;
  final String local = kProviderHost[LlmProviderId.ollama]!;

  group('envoi à un service en ligne (coupé par défaut)', () {
    test('clé Claude rangée mais envoi jamais autorisé : rien ne part vers '
        'un service en ligne, le modèle local répond', () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();

      expect(await nextHost(c), local);
      expect(
        adapter.requests.where((RequestOptions r) => r.uri.host != local),
        isEmpty,
      );
    });

    test('autoriser l\'envoi : Claude répond à la requête suivante, sans '
        'redémarrage, avec sa clé', () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();
      expect(await nextHost(c), local);

      await vm(c).setCloudAllowed(true);

      expect(await nextHost(c), claude);
      expect(adapter.lastHeader('x-api-key'), _claudeKey);
    });

    test('couper l\'envoi : retour immédiat au modèle local', () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), claude);

      await vm(c).setCloudAllowed(false);

      expect(await nextHost(c), local);
    });

    test('l\'autorisation survit au redémarrage, dès la première requête',
        () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer first = await launch();
      await vm(first).setCloudAllowed(true);
      first.dispose();

      final ProviderContainer again = await launch(waitForSettings: false);

      expect(await nextHost(again), claude);
    });

    test('choisir un fournisseur en ligne tant que l\'envoi est coupé est '
        'sans effet', () async {
      store.keys
        ..[LlmProviderId.anthropic] = _claudeKey
        ..[LlmProviderId.openai] = _openAiKey;
      final ProviderContainer c = await launch();

      await vm(c).selectLlmProvider(LlmProviderId.openai);
      expect(await nextHost(c), local);

      // Autoriser ensuite : repli normal (premier configuré), pas OpenAI.
      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), claude);
    });

    test('un choix fait avec l\'envoi autorisé est mis en pause quand on le '
        'coupe, puis revient quand on le rétablit', () async {
      store.keys
        ..[LlmProviderId.anthropic] = _claudeKey
        ..[LlmProviderId.openai] = _openAiKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      await vm(c).selectLlmProvider(LlmProviderId.openai);
      expect(await nextHost(c), openAi);

      await vm(c).setCloudAllowed(false);
      expect(await nextHost(c), local);

      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), openAi);
    });
  });

  group('choix du fournisseur', () {
    Future<ProviderContainer> launchWithTwoKeys() async {
      store.keys
        ..[LlmProviderId.anthropic] = _claudeKey
        ..[LlmProviderId.openai] = _openAiKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      return c;
    }

    test('choisir OpenAI : la requête suivante part chez OpenAI avec sa clé',
        () async {
      final ProviderContainer c = await launchWithTwoKeys();
      expect(await nextHost(c), claude);

      await vm(c).selectLlmProvider(LlmProviderId.openai);

      expect(await nextHost(c), openAi);
      expect(adapter.lastHeader('authorization'), 'Bearer $_openAiKey');
    });

    test('le choix est rangé dans prefs.json sous son identifiant', () async {
      final ProviderContainer c = await launchWithTwoKeys();

      await vm(c).selectLlmProvider(LlmProviderId.openai);

      expect(readPrefs()['llm_provider'], 'openai');
    });

    test('le choix survit au redémarrage, dès la première requête', () async {
      final ProviderContainer first = await launchWithTwoKeys();
      await vm(first).selectLlmProvider(LlmProviderId.openai);
      first.dispose();

      final ProviderContainer again = await launch(waitForSettings: false);

      expect(await nextHost(again), openAi);
    });

    test('choisir le modèle local alors que des clés existent : le modèle '
        'local répond', () async {
      final ProviderContainer c = await launchWithTwoKeys();

      await vm(c).selectLlmProvider(LlmProviderId.ollama);

      expect(await nextHost(c), local);
      expect(readPrefs()['llm_provider'], 'ollama');
    });

    test('le fournisseur choisi n\'est plus configuré (clé retirée) : repli '
        'sur le premier configuré, puis sur le modèle local', () async {
      final ProviderContainer c = await launchWithTwoKeys();
      await vm(c).selectLlmProvider(LlmProviderId.openai);

      await vm(c).removeApiKey(LlmProviderId.openai);
      expect(await nextHost(c), claude);

      await vm(c).removeApiKey(LlmProviderId.anthropic);
      expect(await nextHost(c), local);
    });

    test('choix persisté d\'un fournisseur dont la clé a disparu entre deux '
        'lancements : repli, sans plantage', () async {
      final ProviderContainer first = await launchWithTwoKeys();
      await vm(first).selectLlmProvider(LlmProviderId.openai);
      first.dispose();
      store.keys.remove(LlmProviderId.openai);

      final ProviderContainer again = await launch(waitForSettings: false);

      expect(await nextHost(again), claude);
    });
  });

  group('clés API', () {
    test('enregistrer une clé : utilisée dès la requête suivante, sans '
        'redémarrage', () async {
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), local);

      await vm(c).saveApiKey(LlmProviderId.anthropic, _claudeKey);

      expect(store.keys[LlmProviderId.anthropic], _claudeKey);
      expect(await nextHost(c), claude);
      expect(adapter.lastHeader('x-api-key'), _claudeKey);
    });

    test('remplacer une clé : la nouvelle part dès la requête suivante',
        () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), claude);

      await vm(c).saveApiKey(LlmProviderId.anthropic, 'sk-ant-NEW-KEY-4242');

      await nextHost(c);
      expect(adapter.lastHeader('x-api-key'), 'sk-ant-NEW-KEY-4242');
    });

    test('supprimer une clé : retirée du trousseau, repli immédiat', () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      expect(await nextHost(c), claude);

      await vm(c).removeApiKey(LlmProviderId.anthropic);

      expect(store.keys, isEmpty);
      expect(await nextHost(c), local);
    });

    test('saisie vide ou faite de blancs : rien ne change, la clé existante '
        'reste', () async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();

      for (final String blank in <String>['', '   ', '\n\t']) {
        await vm(c).saveApiKey(LlmProviderId.anthropic, blank);
      }

      expect(store.keys[LlmProviderId.anthropic], _claudeKey);
      expect(store.writeCalls, 0);
      expect(store.deleteCalls, 0);
    });

    test('la clé n\'est jamais écrite dans prefs.json', () async {
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      await vm(c).saveApiKey(LlmProviderId.anthropic, _claudeKey);
      await vm(c).saveApiKey(LlmProviderId.gemini, _geminiKey);
      await vm(c).selectLlmProvider(LlmProviderId.gemini);
      await vm(c).updateLlmModel(LlmProviderId.gemini, 'gemini-custom');

      final String raw = prefsFile.readAsStringSync();
      expect(raw, isNot(contains(_claudeKey)));
      expect(raw, isNot(contains(_geminiKey)));
      expect(raw, isNot(contains('SECRET')));
    });

    test('ni le journal ni la console ne contiennent la clé (enregistrement, '
        'refus du fournisseur, suppression)', () async {
      final Directory dir = Directory.systemTemp.createTempSync('log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File logFile = File('${dir.path}/oats.log');
      Log.writeToFile(logFile.path);
      final List<String> printed = <String>[];
      adapter.reply = const BodyReply(401, '{"error": "invalid x-api-key"}');

      await runZoned(
        () async {
          Log.named('Probe').info('temoin-journal');
          final ProviderContainer c = await launch();
          await vm(c).setCloudAllowed(true);
          await vm(c).saveApiKey(LlmProviderId.anthropic, _claudeKey);
          await nextHost(c);
          await vm(c).removeApiKey(LlmProviderId.anthropic);
        },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              printed.add(line),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final String log = logFile.readAsStringSync();
      expect(log, contains('temoin-journal'));
      expect(log, isNot(contains(_claudeKey)));
      expect(printed.join('\n'), isNot(contains(_claudeKey)));
    });
  });

  group('modèle par fournisseur', () {
    Future<ProviderContainer> launchClaude() async {
      store.keys[LlmProviderId.anthropic] = _claudeKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      return c;
    }

    test('sans modèle choisi : le modèle rapide par défaut', () async {
      final ProviderContainer c = await launchClaude();

      await nextHost(c);

      expect(adapter.bodies.last!['model'], 'claude-haiku-5-5');
    });

    test('modèle modifié : utilisé dès la requête suivante et après un '
        'redémarrage', () async {
      final ProviderContainer c = await launchClaude();

      await vm(c).updateLlmModel(LlmProviderId.anthropic, 'claude-opus-test');
      await nextHost(c);
      expect(adapter.bodies.last!['model'], 'claude-opus-test');
      c.dispose();

      final ProviderContainer again = await launch(waitForSettings: false);
      await nextHost(again);
      expect(adapter.bodies.last!['model'], 'claude-opus-test');
    });

    test('modèle effacé : retour au modèle par défaut', () async {
      final ProviderContainer c = await launchClaude();
      await vm(c).updateLlmModel(LlmProviderId.anthropic, 'claude-opus-test');

      await vm(c).updateLlmModel(LlmProviderId.anthropic, '   ');
      await nextHost(c);

      expect(adapter.bodies.last!['model'], 'claude-haiku-5-5');
    });

    test('chaque fournisseur garde son modèle', () async {
      store.keys[LlmProviderId.openai] = _openAiKey;
      final ProviderContainer c = await launchClaude();
      await vm(c).updateLlmModel(LlmProviderId.anthropic, 'claude-opus-test');

      await vm(c).selectLlmProvider(LlmProviderId.openai);
      await nextHost(c);

      expect(adapter.bodies.last!['model'], 'gpt-6-luna');
    });

    test('Gemini : le modèle choisi est dans l\'URL', () async {
      store.keys[LlmProviderId.gemini] = _geminiKey;
      final ProviderContainer c = await launch();
      await vm(c).setCloudAllowed(true);
      await vm(c).selectLlmProvider(LlmProviderId.gemini);

      await vm(c).updateLlmModel(LlmProviderId.gemini, 'gemini-custom');
      await nextHost(c);

      expect(
        adapter.requests.last.uri.path,
        contains('models/gemini-custom:streamGenerateContent'),
      );
    });

    test('modèle local modifié : utilisé par Ollama', () async {
      final ProviderContainer c = await launch();

      await vm(c).updateLlmModel(LlmProviderId.ollama, 'llama-test');
      await nextHost(c);

      expect(adapter.lastHost, local);
      expect(adapter.bodies.last!['model'], 'llama-test');
    });
  });
}
