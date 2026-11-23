import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';

import '../../helpers/process_host_fakes.dart';

/// Quitter Oats (T3, panneau de barre de menus) : tous les serveurs lancés
/// par l'app s'arrêtent avant la fin du processus, au lieu d'attendre le
/// nettoyage du lancement suivant. Seuls ceux du registre ; un échec sur
/// l'un n'empêche pas les autres et ne remonte jamais.
///
/// API supposée : `Future<void> OwnedProcessRegistry.stopAll()`.
void main() {
  late Directory dir;
  late String stateFile;
  late FakeProcessHost host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('owned_processes_stop_all_');
    stateFile = '${dir.path}/servers.json';
    host = FakeProcessHost();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<int> launch(FakeAsync async, OwnedProcessRegistry registry) {
    final List<int> pids = <int>[];
    registry
        .start('transcription', 'uvx', <String>['voxmlx-serve'], port: 8100)
        .then((Process p) => pids.add(p.pid));
    registry
        .start('llm', 'ollama', <String>['serve'], port: 11434)
        .then((Process p) => pids.add(p.pid));
    async.flushMicrotasks();
    return pids;
  }

  test('arrête tous les serveurs lancés et vide le fichier d\'état', () {
    fakeAsync((FakeAsync async) {
      final OwnedProcessRegistry registry = OwnedProcessRegistry(
        host: host,
        stateFile: stateFile,
      );
      final List<int> pids = launch(async, registry);
      expect(pids, hasLength(2));

      bool done = false;
      registry.stopAll().then((_) => done = true);
      async.elapse(const Duration(seconds: 30));

      expect(done, isTrue);
      for (final int pid in pids) {
        expect(host.table.containsKey(pid), isFalse, reason: 'pid $pid');
      }
      // Lancement suivant : plus rien à nettoyer.
      final FakeProcessHost next = FakeProcessHost(firstPid: 9000)
        ..table.addAll(host.table);
      OwnedProcessRegistry(host: next, stateFile: stateFile).cleanUpLeftovers();
      async.elapse(const Duration(seconds: 30));
      expect(next.kills, isEmpty);
      expect(next.groupKills, isEmpty);
    });
  });

  test('ne touche jamais un processus qu\'il n\'a pas lancé', () {
    fakeAsync((FakeAsync async) {
      host.addForeign(
        const RunningProcess(
          pid: 777,
          groupId: 777,
          startTime: 'Sun Nov 22 08:00:00 2026',
          command: '/opt/tools/uvx voxmlx-serve --port 8000',
        ),
      );
      final OwnedProcessRegistry registry = OwnedProcessRegistry(
        host: host,
        stateFile: stateFile,
      );
      launch(async, registry);

      registry.stopAll();
      async.elapse(const Duration(seconds: 30));

      expect(host.table.containsKey(777), isTrue);
      expect(host.killedPids, isNot(contains(777)));
    });
  });

  test('rien de lancé : aucun signal, fini tout de suite', () {
    fakeAsync((FakeAsync async) {
      bool done = false;
      OwnedProcessRegistry(
        host: host,
        stateFile: stateFile,
      ).stopAll().then((_) => done = true);
      async.flushMicrotasks();

      expect(done, isTrue);
      expect(host.kills, isEmpty);
      expect(host.groupKills, isEmpty);
    });
  });

  test('un serveur qui ignore SIGTERM est tué, dans une borne (< 30 s)', () {
    fakeAsync((FakeAsync async) {
      host.ignoreSigterm = true;
      final OwnedProcessRegistry registry = OwnedProcessRegistry(
        host: host,
        stateFile: stateFile,
      );
      final List<int> pids = launch(async, registry);

      bool done = false;
      registry.stopAll().then((_) => done = true);
      async.elapse(const Duration(seconds: 30));

      expect(done, isTrue);
      expect(pids.where(host.table.containsKey), isEmpty);
    });
  });

  test('un signal qui échoue : pas d\'erreur remontée, les autres serveurs '
      's\'arrêtent quand même', () {
    fakeAsync((FakeAsync async) {
      final _FailingHost failing = _FailingHost(host);
      final OwnedProcessRegistry registry = OwnedProcessRegistry(
        host: failing,
        stateFile: stateFile,
      );
      final List<int> pids = launch(async, registry);
      failing.failingPid = pids.first;

      Object? error;
      bool done = false;
      registry.stopAll().then(
        (_) => done = true,
        onError: (Object e) => error = e,
      );
      async.elapse(const Duration(seconds: 30));

      expect(error, isNull);
      expect(done, isTrue);
      expect(host.table.containsKey(pids.last), isFalse);
    });
  });
}

/// Signaler [failingPid] (seul ou son groupe) lève une erreur du système.
final class _FailingHost implements ProcessHost {
  _FailingHost(this._d);

  final FakeProcessHost _d;
  int? failingPid;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => _d.start(executable, arguments, environment: environment, mode: mode);

  @override
  Future<List<RunningProcess>> running() => _d.running();

  @override
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (pid == failingPid) throw const ProcessException('kill', <String>[]);
    return _d.kill(pid, signal);
  }

  @override
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (groupId == failingPid) throw const ProcessException('kill', <String>[]);
    return _d.killGroup(groupId, signal);
  }

  @override
  int get appGroupId => _d.appGroupId;

  @override
  Future<bool> isPortFree(int port) => _d.isPortFree(port);

  @override
  Future<bool> isHealthy(Uri url) => _d.isHealthy(url);
}
