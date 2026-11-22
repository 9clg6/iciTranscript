import 'dart:async';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Cles API des fournisseurs LLM : rangees dans le trousseau macOS via un
/// canal de plateforme, jamais dans prefs.json ni dans les journaux. Le
/// fournisseur actif et l'etat "configure" se deduisent des cles rangees.
///
/// Contrat du canal `com.icitranscript/keychain` (cote Swift a ecrire) :
/// - `readKey`   {provider} -> String? (null si absente)
/// - `writeKey`  {provider, key} -> null
/// - `deleteKey` {provider} -> null
/// ou `provider` vaut `LlmProviderId.name` (anthropic, openai, gemini, ollama).

const MethodChannel _channel = MethodChannel('com.icitranscript/keychain');
const String _key = 'sk-ant-test-SECRET-0123456789';

/// Trousseau factice : un dictionnaire derriere le canal.
class _FakeKeychain {
  final Map<String, String> items = <String, String>{};
  bool refuseWrites = false;

  Future<Object?> handle(MethodCall call) async {
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
    final String provider = args['provider']! as String;
    switch (call.method) {
      case 'readKey':
        return items[provider];
      case 'writeKey':
        if (refuseWrites) {
          throw PlatformException(
            code: 'errSecAuthFailed',
            message: 'User interaction is not allowed.',
          );
        }
        items[provider] = args['key']! as String;
        return null;
      case 'deleteKey':
        items.remove(provider);
        return null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeKeychain keychain;
  late ApiKeyStore store;

  setUp(() {
    keychain = _FakeKeychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, keychain.handle);
    store = KeychainApiKeyStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('lecture, écriture, suppression', () {
    test('une clé écrite se relit, et seulement pour son fournisseur',
        () async {
      await store.write(LlmProviderId.anthropic, _key);

      expect(await store.read(LlmProviderId.anthropic), _key);
      expect(await store.read(LlmProviderId.openai), isNull);
      expect(keychain.items.values, <String>[_key]);
    });

    test('une clé supprimée se relit null', () async {
      await store.write(LlmProviderId.gemini, _key);

      await store.delete(LlmProviderId.gemini);

      expect(await store.read(LlmProviderId.gemini), isNull);
      expect(keychain.items, isEmpty);
    });

    test('lire une clé jamais écrite renvoie null', () async {
      expect(await store.read(LlmProviderId.openai), isNull);
    });

    test('une clé est rangée sans les blancs autour', () async {
      await store.write(LlmProviderId.openai, '  sk-openai-test \n');

      expect(await store.read(LlmProviderId.openai), 'sk-openai-test');
      expect(keychain.items.values, <String>['sk-openai-test']);
    });

    test('écrire une clé vide ou faite de blancs revient à la supprimer',
        () async {
      for (final String blank in <String>['', '   \n\t']) {
        await store.write(LlmProviderId.anthropic, _key);

        await store.write(LlmProviderId.anthropic, blank);

        expect(await store.read(LlmProviderId.anthropic), isNull,
            reason: 'clé "$blank"');
        expect(keychain.items, isEmpty, reason: 'clé "$blank"');
      }
    });
  });

  group('la clé ne quitte pas le trousseau', () {
    test('écrire, lire et supprimer une clé ne crée aucun fichier, '
        'ni prefs.json ni autre', () async {
      final Directory sandbox = Directory.systemTemp.createTempSync('keys');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final List<String> created = <String>[];

      await IOOverrides.runZoned(
        () async {
          // Temoin : l'interception des fichiers est bien active.
          File('probe.json');

          // Construit dans la zone : un fichier ouvert des le constructeur
          // est intercepte lui aussi.
          final ApiKeyStore zonedStore = KeychainApiKeyStore();
          await zonedStore.write(LlmProviderId.anthropic, _key);
          await zonedStore.read(LlmProviderId.anthropic);
          await zonedStore.delete(LlmProviderId.anthropic);
        },
        // Tout fichier ouvert pendant le test est redirige vers un dossier
        // temporaire : le vrai prefs.json de l'utilisateur n'est jamais
        // touche, et on garde la trace des chemins demandes.
        createFile: (String path) {
          created.add(path);
          return Zone.root.run(
            () => File('${sandbox.path}/${created.length}-${path.split('/').last}'),
          );
        },
      );

      expect(created.first, 'probe.json');
      expect(created.skip(1), isEmpty);
      for (final FileSystemEntity f in sandbox.listSync(recursive: true)) {
        if (f is File) expect(f.readAsStringSync(), isNot(contains(_key)));
      }
    });

    test('ni le journal ni la console ne contiennent la clé, même quand le '
        'trousseau refuse', () async {
      final Directory dir = Directory.systemTemp.createTempSync('log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File logFile = File('${dir.path}/oats.log');
      Log.writeToFile(logFile.path);
      final List<String> printed = <String>[];

      Object? writeError;
      await runZoned(
        () async {
          // Temoin : le journal capture bien ce qui est ecrit.
          Log.named('Probe').info('temoin-journal');

          await store.write(LlmProviderId.openai, _key);
          await store.read(LlmProviderId.openai);
          keychain.refuseWrites = true;
          try {
            await store.write(LlmProviderId.anthropic, _key);
          } on Object catch (e) {
            writeError = e;
          }
          await store.delete(LlmProviderId.openai);
        },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              printed.add(line),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final String log = logFile.readAsStringSync();
      expect(log, contains('temoin-journal'));
      expect(log, isNot(contains(_key)));
      expect(printed.join('\n'), isNot(contains(_key)));
      expect(writeError, isNotNull,
          reason: 'un refus du trousseau ne doit pas passer pour un succès');
      expect(writeError.toString(), isNot(contains(_key)));
    });
  });

  group('fournisseur actif et configuration', () {
    late LlmProviderSelection selection;

    setUp(() => selection = LlmProviderSelection(store));

    test('sans aucune clé, aucun fournisseur cloud n’est configuré et le '
        'fournisseur actif est Ollama (local)', () async {
      expect(await selection.isConfigured(LlmProviderId.anthropic), isFalse);
      expect(await selection.isConfigured(LlmProviderId.openai), isFalse);
      expect(await selection.isConfigured(LlmProviderId.gemini), isFalse);
      expect(await selection.activeProvider(), LlmProviderId.ollama);
    });

    test('avec une seule clé, son fournisseur est configuré et actif',
        () async {
      await store.write(LlmProviderId.openai, 'sk-openai-test');

      expect(await selection.isConfigured(LlmProviderId.openai), isTrue);
      expect(await selection.isConfigured(LlmProviderId.anthropic), isFalse);
      expect(await selection.isConfigured(LlmProviderId.gemini), isFalse);
      expect(await selection.activeProvider(), LlmProviderId.openai);
    });

    test('supprimer la clé du fournisseur actif ramène sur Ollama', () async {
      await store.write(LlmProviderId.gemini, 'gemini-test-key');
      expect(await selection.activeProvider(), LlmProviderId.gemini);

      await store.delete(LlmProviderId.gemini);

      expect(await selection.isConfigured(LlmProviderId.gemini), isFalse);
      expect(await selection.activeProvider(), LlmProviderId.ollama);
    });

    test('Ollama compte toujours comme configuré, sans clé', () async {
      expect(await selection.isConfigured(LlmProviderId.ollama), isTrue);

      await store.write(LlmProviderId.anthropic, _key);

      expect(await selection.isConfigured(LlmProviderId.ollama), isTrue);
    });

    test('sans choix, le premier configuré gagne dans l’ordre anthropic, '
        'openai, gemini', () async {
      await store.write(LlmProviderId.gemini, 'gemini-test-key');
      await store.write(LlmProviderId.openai, 'sk-openai-test');
      expect(await selection.activeProvider(), LlmProviderId.openai);

      await store.write(LlmProviderId.anthropic, _key);
      expect(await selection.activeProvider(), LlmProviderId.anthropic);
    });

    test('le choix de l’utilisateur gagne quand son fournisseur est configuré',
        () async {
      await store.write(LlmProviderId.anthropic, _key);
      await store.write(LlmProviderId.gemini, 'gemini-test-key');

      expect(
        await selection.activeProvider(preferred: LlmProviderId.gemini),
        LlmProviderId.gemini,
      );
      expect(
        await selection.activeProvider(preferred: LlmProviderId.ollama),
        LlmProviderId.ollama,
      );
    });

    test('un choix sans clé est ignoré : premier configuré, sinon Ollama',
        () async {
      expect(
        await selection.activeProvider(preferred: LlmProviderId.openai),
        LlmProviderId.ollama,
      );

      await store.write(LlmProviderId.gemini, 'gemini-test-key');

      expect(
        await selection.activeProvider(preferred: LlmProviderId.openai),
        LlmProviderId.gemini,
      );
    });
  });
}
