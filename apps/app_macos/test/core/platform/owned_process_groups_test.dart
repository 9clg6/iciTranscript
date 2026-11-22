import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';

import '../../helpers/process_host_fakes.dart';

/// Un serveur est un groupe de processus : le meneur (`uvx`, `uv run`) et
/// un enfant Python qui tient le port. Arrêter le serveur, c'est vider le
/// groupe, pas seulement voir le meneur sortir : sinon l'enfant garde le
/// port et le démarrage suivant échoue (« port in use »), sans plus rien
/// pour le rattraper depuis la fin du kill par nom.
///
/// 1. stop : après SIGTERM, attendre (borné par la grâce) qu'il ne reste
///    plus aucun membre du groupe noté ; sinon SIGKILL au GROUPE, par son id
///    noté, même meneur parti. L'entrée n'est retirée que groupe vide.
/// 2. Au lancement : un reste dont le meneur est parti mais dont le groupe
///    a encore un membre cohérent (même groupe, commande cohérente avec la
///    commande notée, démarré au plus tôt au démarrage noté) est nettoyé ;
///    un processus qui ne fait que réutiliser les numéros, jamais.
/// 3. Jamais de signal à un groupe ≤ 1, au groupe de l'app, ni à un groupe
///    que le registre n'a pas noté.
/// 4. Port encore tenu après un arrêt forcé : start lève PortInUse.
///
/// Tout est faux : table des processus, groupes, ports.
void main() {
  const List<String> serverArgs = <String>[
    '--from',
    'voxmlx[server]',
    'voxmlx-serve',
    '--model',
    'm',
    '--port',
    '8100',
  ];
  const String pythonChild =
      '/Users/someone/.cache/uv/archive-v0/abc/bin/python '
      '/Users/someone/.cache/uv/archive-v0/abc/bin/voxmlx-serve '
      '--model m --port 8100';
  const String unrelated = '/Applications/Foo.app/Contents/MacOS/Foo --helper';
  const String otherAppsServer =
      '/Users/someone/.cache/uv/archive-v0/zzz/bin/python '
      '/Users/someone/.cache/uv/archive-v0/zzz/bin/voxmlx-serve '
      '--model m --port 8000';

  late Directory dir;
  late String stateFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('owned_groups_test_');
    stateFile = '${dir.path}/servers.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  OwnedProcessRegistry registry(FakeProcessHost host) =>
      OwnedProcessRegistry(host: host, stateFile: stateFile);

  /// Lancement suivant de l'app : nouvel hôte, même table, mêmes réactions.
  FakeProcessHost nextLaunch(FakeProcessHost from, {int appGroupId = 401}) =>
      FakeProcessHost(firstPid: 9000, appGroupId: appGroupId)
        ..table.addAll(from.table)
        ..termDelays.addAll(from.termDelays)
        ..portHolders.addAll(from.portHolders);

  /// Résout [future] en faisant avancer le temps factice de [by].
  T settle<T>(
    FakeAsync async,
    Future<T> future, {
    Duration by = const Duration(seconds: 30),
  }) {
    late T value;
    Object? error;
    bool done = false;
    future.then(
      (T v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    async.elapse(by);
    if (error != null) throw error!;
    expect(done, isTrue, reason: 'pas terminé après $by');
    return value;
  }

  /// Lance le serveur de transcription ; renvoie le PID du meneur, qui est
  /// aussi l'id de son groupe (sauf [FakeProcessHost.startGroupId]).
  int launch(FakeAsync async, OwnedProcessRegistry processes) => settle(
    async,
    processes.start('transcription', 'uvx', serverArgs, port: 8100),
    by: Duration.zero,
  ).pid;

  Set<ProcessSignal> signalsTo(FakeProcessHost host, int groupId) =>
      <ProcessSignal>{
        for (final ({int groupId, ProcessSignal signal}) k in host.groupKills)
          if (k.groupId == groupId) k.signal,
      };

  group('1. stop vide le groupe, pas seulement le meneur', () {
    test('meneur sorti sur SIGTERM, enfant qui l\'ignore : SIGKILL au groupe '
        'par son id noté, groupe vide, port libre', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost host = FakeProcessHost();
        final OwnedProcessRegistry processes = registry(host);
        final int leader = launch(async, processes);
        host.addChild(
          leader,
          command: pythonChild,
          termDelay: null,
          holdsPort: 8100,
        );

        settle(async, processes.stop('transcription'));

        expect(host.table, isNot(contains(leader)));
        expect(signalsTo(host, leader), contains(ProcessSignal.sigkill));
        expect(host.members(leader), isEmpty);
        expect(settle(async, host.isPortFree(8100)), isTrue);
      });
    });

    test(
      'enfant qui sort 2 s après SIGTERM : stop l\'attend, sans SIGKILL',
      () {
        fakeAsync((FakeAsync async) {
          final FakeProcessHost host = FakeProcessHost();
          final OwnedProcessRegistry processes = registry(host);
          final int leader = launch(async, processes);
          host.addChild(
            leader,
            command: pythonChild,
            termDelay: const Duration(seconds: 2),
          );

          bool stopped = false;
          processes.stop('transcription').then((_) => stopped = true);
          async.elapse(const Duration(seconds: 1));
          expect(stopped, isFalse, reason: 'un membre du groupe vit encore');

          async.elapse(const Duration(seconds: 3));
          expect(stopped, isTrue);
          expect(host.members(leader), isEmpty);
          expect(<ProcessSignal>{
            for (final k in host.kills) k.signal,
            for (final k in host.groupKills) k.signal,
          }, isNot(contains(ProcessSignal.sigkill)));
        });
      },
    );

    test('l\'app meurt pendant l\'arrêt (meneur parti, enfant vivant) : '
        'l\'entrée est encore là, le lancement suivant vide le groupe', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost host = FakeProcessHost();
        final OwnedProcessRegistry processes = registry(host);
        final int leader = launch(async, processes);
        host.addChild(leader, command: pythonChild, termDelay: null);

        processes.stop('transcription');
        async.elapse(const Duration(seconds: 1));
        expect(host.table, isNot(contains(leader)));

        final FakeProcessHost next = nextLaunch(host);
        settle(async, registry(next).cleanUpLeftovers());

        expect(next.killedGroups, <int>{leader});
        expect(next.members(leader), isEmpty);
      });
    });

    test('le meneur meurt seul pendant que l\'app tourne : l\'entrée reste '
        'tant que son groupe a un membre', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost host = FakeProcessHost();
        final int leader = launch(async, registry(host));
        host.addChild(leader, command: pythonChild, termDelay: null);

        host.processes[leader]!.exit(1);
        async.elapse(const Duration(seconds: 1));

        final FakeProcessHost next = nextLaunch(host);
        settle(async, registry(next).cleanUpLeftovers());

        expect(next.killedGroups, <int>{leader});
        expect(next.members(leader), isEmpty);
      });
    });

    test('après un arrêt forcé, le démarrage suivant reprend le port', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost host = FakeProcessHost();
        final OwnedProcessRegistry processes = registry(host);
        final int leader = launch(async, processes);
        host.addChild(
          leader,
          command: pythonChild,
          termDelay: null,
          holdsPort: 8100,
        );
        settle(async, processes.stop('transcription'));

        launch(async, processes);

        expect(host.started, hasLength(2));
      });
    });
  });

  group('2. au lancement : meneur parti, groupe encore peuplé', () {
    /// Lancement précédent sur [previous], app tuée net : le meneur est mort,
    /// [setUpGroup] ajoute ce qui reste dans la table. Renvoie le groupe
    /// noté et l'hôte du lancement suivant.
    (int, FakeProcessHost) crashedLaunch(
      FakeAsync async,
      void Function(FakeProcessHost previous, int leader) setUpGroup,
    ) {
      final FakeProcessHost previous = FakeProcessHost();
      final int leader = launch(async, registry(previous));
      setUpGroup(previous, leader);
      final FakeProcessHost next = nextLaunch(previous)..table.remove(leader);
      return (leader, next);
    }

    test('enfant cohérent (même groupe, même serveur, démarré après) : '
        'groupe vidé', () {
      fakeAsync((FakeAsync async) {
        final (int group, FakeProcessHost next) = crashedLaunch(
          async,
          (FakeProcessHost h, int leader) =>
              h.addChild(leader, command: pythonChild, termDelay: null),
        );

        settle(async, registry(next).cleanUpLeftovers());

        expect(next.killedGroups, <int>{group});
        expect(next.members(group), isEmpty);
      });
    });

    test('même PID, démarrage plus tardif, autre commande : épargné', () {
      fakeAsync((FakeAsync async) {
        final (int group, FakeProcessHost next) = crashedLaunch(
          async,
          (FakeProcessHost h, int leader) {},
        );
        // Le PID (donc le numéro de groupe qu'il mène) est réutilisé.
        next.addForeign(
          RunningProcess(
            pid: group,
            groupId: group,
            startTime: FakeProcessHost.lstart(3600),
            command: unrelated,
          ),
        );

        settle(async, registry(next).cleanUpLeftovers());

        expect(next.kills, isEmpty);
        expect(next.groupKills, isEmpty);
        expect(next.table, contains(group));
      });
    });

    for (final (String name, String command) in <(String, String)>[
      ('commande sans rapport', unrelated),
      ('serveur d\'une autre app (autre port)', otherAppsServer),
    ]) {
      test('même id de groupe, $name : épargné', () {
        fakeAsync((FakeAsync async) {
          final (int group, FakeProcessHost next) = crashedLaunch(
            async,
            (FakeProcessHost h, int leader) {},
          );
          next.addForeign(
            RunningProcess(
              pid: 9500,
              groupId: group,
              startTime: FakeProcessHost.lstart(3600),
              command: command,
            ),
          );

          settle(async, registry(next).cleanUpLeftovers());

          expect(next.kills, isEmpty);
          expect(next.groupKills, isEmpty);
          expect(next.table, contains(9500));
        });
      });
    }

    test('même groupe, commande cohérente, mais démarré AVANT le démarrage '
        'noté : épargné', () {
      fakeAsync((FakeAsync async) {
        final (int group, FakeProcessHost next) = crashedLaunch(
          async,
          (FakeProcessHost h, int leader) {},
        );
        next.addForeign(
          RunningProcess(
            pid: 9500,
            groupId: group,
            startTime: 'Sun Nov 22 09:00:00 2026',
            command: pythonChild,
          ),
        );

        settle(async, registry(next).cleanUpLeftovers());

        expect(next.kills, isEmpty);
        expect(next.groupKills, isEmpty);
      });
    });
  });

  group('3. groupes jamais signalés', () {
    for (final int bad in <int>[0, 1]) {
      test('groupe noté $bad : aucun signal de groupe, ni à l\'arrêt ni au '
          'lancement suivant', () {
        fakeAsync((FakeAsync async) {
          final FakeProcessHost host = FakeProcessHost()..startGroupId = bad;
          final OwnedProcessRegistry processes = registry(host);
          final int leader = launch(async, processes);
          host.addChild(leader, command: pythonChild, termDelay: null);
          host.processes[leader]!.exit(1);
          async.elapse(const Duration(seconds: 1));

          final FakeProcessHost next = nextLaunch(host);
          settle(async, registry(next).cleanUpLeftovers());

          expect(host.groupKills, isEmpty);
          expect(next.groupKills, isEmpty);
        });
      });
    }

    test('serveur resté dans le groupe de l\'app : stop ne signale jamais ce '
        'groupe', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost host = FakeProcessHost(appGroupId: 400)
          ..startGroupId = 400;
        final OwnedProcessRegistry processes = registry(host);
        final int leader = launch(async, processes);
        host.addChild(leader, command: pythonChild, termDelay: null);

        settle(async, processes.stop('transcription'));

        expect(host.killedGroups, isNot(contains(400)));
      });
    });

    test('groupe noté devenu celui de l\'app au lancement suivant : jamais '
        'signalé', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost previous = FakeProcessHost();
        final int leader = launch(async, registry(previous));
        previous.addChild(leader, command: pythonChild, termDelay: null);
        final FakeProcessHost next = nextLaunch(previous, appGroupId: leader)
          ..table.remove(leader);

        settle(async, registry(next).cleanUpLeftovers());

        expect(next.killedGroups, isNot(contains(leader)));
      });
    });

    test('un groupe que le registre n\'a pas noté n\'est jamais signalé', () {
      fakeAsync((FakeAsync async) {
        final FakeProcessHost previous = FakeProcessHost();
        final int leader = launch(async, registry(previous));
        previous.addChild(leader, command: pythonChild, termDelay: null);
        final FakeProcessHost next = nextLaunch(previous)
          ..table.remove(leader)
          // L'app installée : son serveur, sans meneur visible, dans son
          // propre groupe.
          ..addForeign(
            RunningProcess(
              pid: 700,
              groupId: 700,
              startTime: FakeProcessHost.lstart(5),
              command: otherAppsServer,
            ),
          )
          ..addForeign(
            RunningProcess(
              pid: 701,
              groupId: 700,
              startTime: FakeProcessHost.lstart(6),
              command: pythonChild,
            ),
          );

        settle(async, registry(next).cleanUpLeftovers());

        expect(next.killedGroups, <int>{leader});
        expect(next.killedPids.intersection(<int>{700, 701}), isEmpty);
        expect(next.table.keys, containsAll(<int>[700, 701]));
      });
    });
  });

  test('4. port encore tenu après un arrêt forcé : PortInUse, rien de plus', () {
    fakeAsync((FakeAsync async) {
      final FakeProcessHost host = FakeProcessHost();
      final OwnedProcessRegistry processes = registry(host);
      final int leader = launch(async, processes);
      host.addChild(leader, command: pythonChild, termDelay: null);
      // Un processus sorti du groupe (autre groupe, jamais noté) tient le port.
      host.addForeign(
        RunningProcess(
          pid: 6000,
          groupId: 6000,
          startTime: FakeProcessHost.lstart(2),
          command: pythonChild,
        ),
      );
      host.portHolders[8100] = 6000;

      settle(async, processes.stop('transcription'));

      expect(
        () => settle(
          async,
          processes.start('transcription', 'uvx', serverArgs, port: 8100),
        ),
        throwsA(
          isA<PortInUseException>().having(
            (PortInUseException e) => e.port,
            'port',
            8100,
          ),
        ),
      );
      expect(host.started, hasLength(1));
      expect(host.killedPids, isNot(contains(6000)));
      expect(host.killedGroups, isNot(contains(6000)));
    });
  });
}
