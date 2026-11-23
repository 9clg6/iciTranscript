import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/process_host_fakes.dart' hide eventually;
import '../../helpers/settings_fakes.dart';

/// Démon Ollama et registre des serveurs de l'app (rôle `ollama`, port
/// 11434). Vrai `OllamaService` et vrai `OwnedProcessRegistry` ; hôte de
/// processus factice, transport Dio factice pour le démon : aucun vrai
/// processus, aucun vrai localhost.
///
/// API lue dans le code : `OllamaService({OwnedProcessRegistry? processes,
/// Dio? dio})`, `ensureReady`, `isInstalled({model})`, `dispose()` (= sortie
/// de l'app, appelé par `ollamaServiceProvider`), `cleanUpLeftovers()` du
/// registre au lancement.
void main() {
  const int port = 11434;
  late Directory state;
  late FakeProcessHost inner;
  late _OllamaHost host;

  /// Binaire Ollama présent dans le dossier d'outils (de test).
  void binaryOnDisk() {
    final Directory bin = Directory('${toolsDirectory()}/bin')
      ..createSync(recursive: true);
    File('${bin.path}/ollama').writeAsStringSync('#!/bin/sh');
    File('${bin.path}/libggml-base.dylib').writeAsStringSync('');
  }

  /// Manifeste du modèle `mistral` (téléchargement terminé).
  Directory manifest() => Directory(
    '${toolsDirectory()}/models/manifests/registry.ollama.ai/library/mistral',
  );

  setUp(() {
    binaryOnDisk();
    if (manifest().existsSync()) manifest().deleteSync(recursive: true);
    state = Directory.systemTemp.createTempSync('oats_servers_');
    inner = FakeProcessHost();
    host = _OllamaHost(inner);
  });
  tearDown(() {
    if (state.existsSync()) state.deleteSync(recursive: true);
  });

  OwnedProcessRegistry registry([String name = 'servers.json']) =>
      OwnedProcessRegistry(host: host, stateFile: '${state.path}/$name');

  OllamaService service(
    OwnedProcessRegistry processes, {
    _DaemonAdapter? daemon,
  }) => OllamaService(
    processes: processes,
    dio: Dio()..httpClientAdapter = daemon ?? _DaemonAdapter(),
  );

  bool recordsOllama(String name) {
    final File f = File('${state.path}/$name');
    return f.existsSync() && f.readAsStringSync().contains('ollama');
  }

  group(
    '1. démon déjà là, pas lancé par l\'app (Ollama de l\'utilisateur)',
    () {
      setUp(() => host.foreignDaemonUp = true);

      test('il sert tel quel : rien n\'est lancé ni noté', () async {
        final OllamaService s = service(registry());

        await s.ensureReady();

        expect(inner.started, isEmpty);
        expect(recordsOllama('servers.json'), isFalse);
      });

      test('jamais arrêté : ni à la sortie de l\'app, ni par le nettoyage du '
          'lancement suivant', () async {
        final OwnedProcessRegistry r = registry();
        final OllamaService s = service(r);
        await s.ensureReady();

        await s.dispose();
        await registry().cleanUpLeftovers();

        expect(inner.kills, isEmpty);
        expect(inner.groupKills, isEmpty);
      });
    },
  );

  group('2. rien ne répond', () {
    test('l\'app lance `ollama serve` par le registre, attend la santé et le '
        'note', () async {
      final OllamaService s = service(registry());

      await s.ensureReady();

      expect(inner.started, hasLength(1));
      expect(inner.started.single.executable, endsWith('ollama'));
      expect(inner.started.single.arguments, <String>['serve']);
      expect(inner.healthChecks.map((Uri u) => u.port).toSet(), <int>{port});
      expect(recordsOllama('servers.json'), isTrue);
    });

    test('à la sortie, seul ce démon-là est arrêté', () async {
      inner.addForeign(
        const RunningProcess(
          pid: 777,
          groupId: 777,
          startTime: 'Sun Nov 22 09:00:00 2026',
          command: 'ollama serve',
        ),
      );
      final OllamaService s = service(registry());
      await s.ensureReady();
      final int ours = inner.processes.keys.single;

      await s.dispose();

      expect(inner.killedPids, contains(ours));
      expect(inner.killedPids, isNot(contains(777)));
      expect(inner.killedGroups, isNot(contains(777)));
      expect(inner.table.containsKey(777), isTrue);
    });
  });

  group('3. port 11434 tenu par un autre programme (santé jamais bonne)', () {
    setUp(() => inner.busyPorts.add(port));

    test('rien n\'est tué ni lancé ; le démarrage échoue', () async {
      final OllamaService s = service(registry());

      await expectLater(s.ensureReady(), throwsA(anything));

      expect(inner.started, isEmpty);
      expect(inner.kills, isEmpty);
      expect(inner.groupKills, isEmpty);
    });

    testWidgets('la note affiche « injoignable », rien ne reste lancé', (
      WidgetTester tester,
    ) async {
      manifest().createSync(recursive: true);
      // Envoi coupé, modèle choisi = mistral (défaut) : le manifeste
      // ci-dessus suffit.
      resetPrefs();
      final AppDatabase db = memoryDatabase();
      addTearDown(db.close);
      final RecordingHttpAdapter llm = RecordingHttpAdapter();
      final OllamaService s = service(registry());
      final List<Override> overrides = <Override>[
        databaseProvider.overrideWithValue(db),
        ollamaServiceProvider.overrideWithValue(s),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = llm),
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(kOllamaReady),
        ),
      ];
      await tester.runAsync(() async {
        final ProviderContainer c = ProviderContainer(overrides: overrides);
        await seedNote(c, kShortMeeting);
        c.dispose();
      });
      await pumpLocalized(
        tester,
        SessionDetailScreen(sessionId: 's1', onClose: () {}),
        settle: false,
        overrides: overrides,
      );
      for (
        int i = 0;
        i < 30 && find.text('history.detail.summarize'.tr()).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await settle(tester, frames: 2);
      }

      await tester.tap(find.text('history.detail.summarize'.tr()));
      final Finder loading = find.text('history.detail.summary_loading'.tr());
      await settle(tester, frames: 2);
      for (int i = 0; i < 50 && loading.evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await settle(tester, frames: 2);
      }

      expect(find.textContaining('llm.error.unreachable'.tr()), findsOneWidget);
      expect(llm.requests, isEmpty);
      expect(inner.started, isEmpty);
      expect(inner.kills, isEmpty);
    });
  });

  group('4. téléchargement du modèle en cours quand l\'app se ferme', () {
    test('le démon lancé par l\'app est arrêté', () async {
      final _DaemonAdapter daemon = _DaemonAdapter(models: <String>[])
        ..pullHangs = true;
      final OllamaService s = service(registry(), daemon: daemon);
      unawaited(s.ensureReady().then((_) {}, onError: (Object _) {}));
      await eventually(() => expect(daemon.pulls, greaterThan(0)));
      expect(daemon.pulls, 1, reason: 'téléchargement en cours');
      final int ours = inner.processes.keys.single;

      await s.dispose();

      expect(inner.killedPids, contains(ours));
    });

    test('au lancement suivant : « non installé », installation proposée de '
        'nouveau, pas d\'état « installation en cours » figé', () async {
      // Lancement précédent : démon lancé puis arrêté pendant le
      // téléchargement ; le manifeste n'a jamais été écrit.
      final _DaemonAdapter daemon = _DaemonAdapter(models: <String>[])
        ..pullHangs = true;
      final OllamaService first = service(registry(), daemon: daemon);
      unawaited(first.ensureReady().then((_) {}, onError: (Object _) {}));
      await eventually(() => expect(daemon.pulls, greaterThan(0)));
      await first.dispose();

      resetPrefs();
      final OllamaService next = service(registry());
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[ollamaServiceProvider.overrideWithValue(next)],
      );
      addTearDown(c.dispose);
      c.listen(ollamaSetupViewModelProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final OllamaSetupState s = c.read(ollamaSetupViewModelProvider);
      expect(s.isReady, isFalse);
      expect(s.stage, anyOf(OllamaSetupStage.idle, OllamaSetupStage.error));
    });
  });

  group('5. dev et release partagent le démon', () {
    test('un lancement sur données de dev n\'arrête jamais le démon noté '
        'par le fichier d\'état d\'un autre dossier de données', () async {
      final OllamaService release = service(registry('release.json'));
      await release.ensureReady();
      final int releaseDaemon = inner.processes.keys.single;
      expect(recordsOllama('release.json'), isTrue);

      final OwnedProcessRegistry devRegistry = registry('dev.json');
      await devRegistry.cleanUpLeftovers();
      final OllamaService dev = service(devRegistry);
      await dev.ensureReady();
      await dev.dispose();

      expect(inner.started, hasLength(1), reason: 'le dev réutilise le démon');
      expect(inner.killedPids, isNot(contains(releaseDaemon)));
      expect(inner.table.containsKey(releaseDaemon), isTrue);
      expect(recordsOllama('dev.json'), isFalse);
    });
  });
}

/// Hôte où le démon répond quand un `ollama serve` lancé ici tourne, ou
/// quand [foreignDaemonUp] (démon d'un autre programme) ; port pris selon
/// [FakeProcessHost.busyPorts].
final class _OllamaHost implements ProcessHost {
  _OllamaHost(this.inner);

  final FakeProcessHost inner;
  bool foreignDaemonUp = false;

  bool get _ownDaemonUp => inner.processes.keys.any(inner.table.containsKey);

  @override
  Future<bool> isHealthy(Uri url) async {
    inner.healthChecks.add(url);
    if (inner.busyPorts.contains(url.port)) return false;
    return foreignDaemonUp || _ownDaemonUp;
  }

  @override
  Future<bool> isPortFree(int port) async =>
      !foreignDaemonUp && !_ownDaemonUp && await inner.isPortFree(port);

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) =>
      inner.start(executable, arguments, environment: environment, mode: mode);

  @override
  Future<List<RunningProcess>> running() => inner.running();

  @override
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) =>
      inner.kill(pid, signal);

  @override
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]) =>
      inner.killGroup(groupId, signal);

  @override
  int get appGroupId => inner.appGroupId;
}

/// Démon local factice : `/api/tags` liste [models] ; `/api/pull` répond
/// « success » ou, si [pullHangs], ne finit jamais.
class _DaemonAdapter implements HttpClientAdapter {
  _DaemonAdapter({this.models = const <String>['mistral:latest']});

  final List<String> models;
  bool pullHangs = false;
  int pulls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String path = options.uri.path;
    if (path.endsWith('/api/tags')) {
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'models': <Map<String, String>>[
            for (final String m in models) <String, String>{'name': m},
          ],
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }
    if (path.endsWith('/api/pull')) {
      pulls++;
      final StreamController<Uint8List> body = StreamController<Uint8List>();
      body.add(utf8.encode('{"status":"pulling manifest"}\n'));
      if (!pullHangs) {
        body.add(utf8.encode('{"status":"success"}\n'));
        unawaited(body.close());
      }
      return ResponseBody(body.stream, 200);
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
