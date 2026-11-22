import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';

import '../../helpers/process_host_fakes.dart';

/// L'app n'arrête que les processus qu'elle a lancés elle-même. Elle note le
/// PID de chaque serveur lancé, avec son heure de démarrage et sa commande
/// (un PID est réutilisé par le système), dans un petit fichier de son
/// propre dossier de données ; elle retire l'entrée à l'arrêt propre ; au
/// lancement suivant elle ne nettoie que les restes notés dont le PID a
/// encore la même identité. Jamais de kill par nom, jamais de « libérer le
/// port » sur un processus qui n'est pas à elle : un port pris par un autre
/// programme est une erreur claire.
///
/// Aucun vrai processus : la table des processus et les ports sont ceux du
/// faux. Le fichier d'état vit dans un dossier temporaire du test.
void main() {
  const String installedVoxmlx =
      '/Users/someone/.local/bin/uv tool uvx voxmlx-serve --port 8000';

  group('leftoversToKill (fonction pure)', () {
    const OwnedProcess recorded = OwnedProcess(
      role: 'transcription',
      pid: 4242,
      startTime: 'Sun Nov 22 09:00:00 2026',
      command: 'uvx voxmlx-serve --port 8100',
    );

    RunningProcess same(OwnedProcess p) =>
        RunningProcess(pid: p.pid, startTime: p.startTime, command: p.command);

    test('rien de noté : rien à tuer, même si un voxmlx tourne', () {
      expect(
        leftoversToKill(<OwnedProcess>[], <RunningProcess>[
          const RunningProcess(
            pid: 777,
            startTime: 'Sun Nov 22 08:00:00 2026',
            command: installedVoxmlx,
          ),
        ]),
        isEmpty,
      );
    });

    test('un reste noté, toujours vivant, même identité : à tuer', () {
      expect(
        leftoversToKill(
          <OwnedProcess>[recorded],
          <RunningProcess>[same(recorded)],
        ).map((OwnedProcess p) => p.pid),
        <int>[4242],
      );
    });

    test('un PID noté qui ne tourne plus : rien à tuer', () {
      expect(
        leftoversToKill(<OwnedProcess>[recorded], <RunningProcess>[]),
        isEmpty,
      );
    });

    test('PID réutilisé par un autre programme (autre heure de démarrage) : '
        'épargné', () {
      expect(
        leftoversToKill(
          <OwnedProcess>[recorded],
          <RunningProcess>[
            RunningProcess(
              pid: recorded.pid,
              startTime: 'Sun Nov 22 11:30:00 2026',
              command: recorded.command,
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('PID réutilisé, même heure mais autre commande : épargné', () {
      expect(
        leftoversToKill(
          <OwnedProcess>[recorded],
          <RunningProcess>[
            RunningProcess(
              pid: recorded.pid,
              startTime: recorded.startTime,
              command: installedVoxmlx,
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('plusieurs entrées : seules celles qui correspondent', () {
      const OwnedProcess gone = OwnedProcess(
        role: 'diarization',
        pid: 4300,
        startTime: 'Sun Nov 22 09:00:05 2026',
        command: 'uv run nemotron_diar_mlx.server --port 8101',
      );
      const OwnedProcess reused = OwnedProcess(
        role: 'ollama',
        pid: 4400,
        startTime: 'Sun Nov 22 09:00:09 2026',
        command: 'ollama serve',
      );
      expect(
        leftoversToKill(
          <OwnedProcess>[recorded, gone, reused],
          <RunningProcess>[
            same(recorded),
            const RunningProcess(
              pid: 4400,
              startTime: 'Sun Nov 22 12:00:00 2026',
              command: 'ollama serve',
            ),
            const RunningProcess(
              pid: 777,
              startTime: 'Sun Nov 22 08:00:00 2026',
              command: installedVoxmlx,
            ),
          ],
        ).map((OwnedProcess p) => p.pid),
        <int>[4242],
      );
    });
  });

  test('le fichier d\'état vit dans le dossier de données de l\'app', () {
    expect(ownedProcessesFile(), startsWith('${appDataDirectory()}/'));
    expect(ownedProcessesFile(), isNot(startsWith('${toolsDirectory()}/')));
  });

  group('OwnedProcessRegistry', () {
    late Directory dir;
    late String stateFile;
    late FakeProcessHost host;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('owned_processes_test_');
      stateFile = '${dir.path}/servers.json';
      host = FakeProcessHost();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    OwnedProcessRegistry registry([FakeProcessHost? on]) =>
        OwnedProcessRegistry(host: on ?? host, stateFile: stateFile);

    /// Lancement suivant de l'app : nouvel hôte, même table des processus.
    FakeProcessHost nextLaunch() =>
        FakeProcessHost(firstPid: 9000)..table.addAll(host.table);

    test(
      'un serveur lancé puis l\'app tuée : nettoyé au lancement suivant',
      () async {
        final Process server = await registry().start(
          'transcription',
          'uvx',
          <String>['voxmlx-serve', '--port', '8100'],
          port: 8100,
        );

        final FakeProcessHost next = nextLaunch();
        await registry(next).cleanUpLeftovers();

        expect(next.killedPids, <int>{server.pid});
      },
    );

    test(
      'arrêt propre : l\'entrée est retirée, rien à nettoyer ensuite',
      () async {
        final OwnedProcessRegistry processes = registry();
        final Process server = await processes.start(
          'transcription',
          'uvx',
          <String>['voxmlx-serve'],
          port: 8100,
        );
        await processes.stop('transcription');

        expect(host.killedPids, <int>{server.pid});

        // Le PID est réutilisé tel quel par un autre programme : rien noté,
        // donc rien tué.
        final FakeProcessHost next = nextLaunch()
          ..addForeign(
            RunningProcess(
              pid: server.pid,
              startTime: 'Sun Nov 22 10:00:00 2026',
              command: installedVoxmlx,
            ),
          );
        await registry(next).cleanUpLeftovers();
        expect(next.kills, isEmpty);
      },
    );

    test(
      'le serveur de l\'app installée n\'est jamais tué au lancement',
      () async {
        host.addForeign(
          const RunningProcess(
            pid: 777,
            startTime: 'Sun Nov 22 08:00:00 2026',
            command: installedVoxmlx,
          ),
        );
        await registry().start('transcription', 'uvx', <String>[
          'voxmlx-serve',
          '--port',
          '8100',
        ], port: 8100);

        final FakeProcessHost next = nextLaunch();
        await registry(next).cleanUpLeftovers();

        expect(next.killedPids, isNot(contains(777)));
      },
    );

    test(
      'PID d\'un reste réutilisé par un autre programme : épargné',
      () async {
        final Process server = await registry().start(
          'diarization',
          'uv',
          <String>['run', 'nemotron_diar_mlx.server'],
          port: 8101,
        );

        final FakeProcessHost next = FakeProcessHost(firstPid: 9000)
          ..addForeign(
            RunningProcess(
              pid: server.pid,
              startTime: 'Sun Nov 22 11:59:59 2026',
              command: installedVoxmlx,
            ),
          );
        await registry(next).cleanUpLeftovers();

        expect(next.kills, isEmpty);
      },
    );

    test('arrêter un rôle jamais lancé ne tue rien', () async {
      host.addForeign(
        const RunningProcess(
          pid: 777,
          startTime: 'Sun Nov 22 08:00:00 2026',
          command: installedVoxmlx,
        ),
      );
      await registry().stop('transcription');

      expect(host.kills, isEmpty);
    });

    test('arrêter un rôle ne touche pas aux autres serveurs lancés', () async {
      final OwnedProcessRegistry processes = registry();
      final Process transcription = await processes.start(
        'transcription',
        'uvx',
        <String>['voxmlx-serve'],
        port: 8100,
      );
      final Process diarization = await processes.start(
        'diarization',
        'uv',
        <String>['run', 'nemotron_diar_mlx.server'],
        port: 8101,
      );
      await processes.stop('diarization');

      expect(host.killedPids, <int>{diarization.pid});
      expect(host.table, contains(transcription.pid));
    });

    test('un serveur qui ignore SIGTERM reçoit SIGKILL, lui seul', () {
      fakeAsync((FakeAsync async) {
        host.ignoreSigterm = true;
        final OwnedProcessRegistry processes = registry();
        late Process server;
        processes
            .start('transcription', 'uvx', <String>['voxmlx-serve'], port: 8100)
            .then((Process p) => server = p);
        async.flushMicrotasks();

        processes.stop('transcription');
        async.elapse(const Duration(seconds: 30));

        expect(
          host.kills,
          contains((pid: server.pid, signal: ProcessSignal.sigkill)),
        );
        expect(host.killedPids, <int>{server.pid});
        expect(host.table, isNot(contains(server.pid)));
      });
    });

    group('port pris par un autre programme', () {
      setUp(() {
        host.busyPorts.add(8000);
        host.addForeign(
          const RunningProcess(
            pid: 777,
            startTime: 'Sun Nov 22 08:00:00 2026',
            command: installedVoxmlx,
          ),
        );
      });

      test('erreur claire « port 8000 is used by another program »', () async {
        await expectLater(
          registry().start('transcription', 'uvx', <String>[
            'voxmlx-serve',
          ], port: 8000),
          throwsA(
            isA<PortInUseException>()
                .having((PortInUseException e) => e.port, 'port', 8000)
                .having(
                  (PortInUseException e) => e.message,
                  'message',
                  'port 8000 is used by another program',
                ),
          ),
        );
      });

      test('rien n\'est tué, rien n\'est lancé, rien n\'est noté', () async {
        await expectLater(
          registry().start('transcription', 'uvx', <String>[
            'voxmlx-serve',
          ], port: 8000),
          throwsA(isA<PortInUseException>()),
        );

        expect(host.kills, isEmpty);
        expect(host.started, isEmpty);
        final FakeProcessHost next = nextLaunch();
        await registry(next).cleanUpLeftovers();
        expect(next.kills, isEmpty);
      });
    });

    group('lancement sans reste à nettoyer', () {
      test('pas de fichier d\'état : rien tué, pas même un ps lancé', () async {
        host.addForeign(
          const RunningProcess(
            pid: 777,
            startTime: 'Sun Nov 22 08:00:00 2026',
            command: installedVoxmlx,
          ),
        );
        await registry().cleanUpLeftovers();

        expect(host.kills, isEmpty);
        expect(host.snapshots, 0);
      });

      test('fichier d\'état illisible : rien tué, pas d\'exception', () async {
        File(stateFile).writeAsStringSync('{not json');
        host.addForeign(
          const RunningProcess(
            pid: 777,
            startTime: 'Sun Nov 22 08:00:00 2026',
            command: installedVoxmlx,
          ),
        );

        await registry().cleanUpLeftovers();

        expect(host.kills, isEmpty);
      });

      test(
        'table des processus illisible : rien tué, pas d\'exception',
        () async {
          await registry().start('transcription', 'uvx', <String>[
            'voxmlx-serve',
          ], port: 8100);
          final FakeProcessHost next = nextLaunch()..failSnapshots = true;

          await registry(next).cleanUpLeftovers();

          expect(next.kills, isEmpty);
        },
      );
    });
  });
}
