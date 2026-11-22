import 'dart:async';
import 'dart:io';

import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

import '../../helpers/process_host_fakes.dart';

/// Le serveur de transcription (voxmlx-serve) : lancé sur le port du
/// lancement (8000 en release, 8100 sur données de dev), sondé sur ce même
/// port, arrêté sans jamais toucher à un processus que l'app n'a pas lancé.
/// Un port déjà pris par un autre programme n'est pas « libéré » : c'est une
/// erreur claire.
///
/// Hôte de processus factice : aucun vrai processus, aucun vrai port.
void main() {
  const List<String> args = <String>[
    '--from',
    'voxmlx[server]',
    'voxmlx-serve',
    '--model',
    'm',
  ];
  const RunningProcess installedServer = RunningProcess(
    pid: 777,
    startTime: 'Sun Nov 22 08:00:00 2026',
    command: '/Users/someone/.local/bin/uvx voxmlx-serve --port 8000',
  );

  late Directory dir;
  late FakeProcessHost host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('process_manager_test_');
    host = FakeProcessHost()..addForeign(installedServer);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProcessManagerChannel channel(AppBuildMode mode) => ProcessManagerChannel(
    processes: OwnedProcessRegistry(
      host: host,
      stateFile: '${dir.path}/servers.json',
    ),
    ports: resolveServerPorts(const <String, String>{
      'HOME': '/Users/someone',
    }, buildMode: mode),
  );

  for (final (AppBuildMode mode, int port) in <(AppBuildMode, int)>[
    (AppBuildMode.release, 8000),
    (AppBuildMode.debug, 8100),
  ]) {
    group('${mode.name} : port $port', () {
      test('le serveur est lancé avec --port $port', () async {
        await channel(mode).startServer(command: 'uvx', args: args);

        expect(host.started, hasLength(1));
        expect(host.commandLine(0), contains('--port $port'));
      });

      test('la santé est sondée sur ce même port', () async {
        await channel(mode).startServer(command: 'uvx', args: args);

        expect(host.healthChecks, isNotEmpty);
        expect(host.healthChecks.toSet(), <Uri>{
          Uri.parse('http://127.0.0.1:$port/health'),
        });
      });
    });
  }

  test('démarrer ne tue rien, pas même un voxmlx d\'une autre app', () async {
    await channel(AppBuildMode.debug).startServer(command: 'uvx', args: args);

    expect(host.kills, isEmpty);
    expect(host.table, contains(installedServer.pid));
  });

  test('arrêter ne tue que le serveur lancé', () async {
    final ProcessManagerChannel ml = channel(AppBuildMode.debug);
    await ml.startServer(command: 'uvx', args: args);
    final int ours = host.processes.keys.single;

    await ml.stopServer();

    expect(host.killedPids, <int>{ours});
    expect(host.table, contains(installedServer.pid));
    expect(await ml.getServerState(), ServerState.stopped);
  });

  test(
    'relancer arrête l\'ancien serveur lancé, pas celui d\'une autre app',
    () async {
      final ProcessManagerChannel ml = channel(AppBuildMode.debug);
      await ml.startServer(command: 'uvx', args: args);
      final int first = host.processes.keys.single;

      await ml.startServer(command: 'uvx', args: args);

      expect(host.started, hasLength(2));
      expect(host.killedPids, <int>{first});
    },
  );

  group('port pris par un autre programme', () {
    setUp(() => host.busyPorts.add(8000));

    test(
      'le démarrage échoue avec « port 8000 is used by another program »',
      () async {
        await expectLater(
          channel(AppBuildMode.release).startServer(command: 'uvx', args: args),
          throwsA(
            isA<PortInUseException>().having(
              (PortInUseException e) => e.toString(),
              'message',
              contains('port 8000 is used by another program'),
            ),
          ),
        );
      },
    );

    test('l\'état du serveur passe en erreur', () async {
      final ProcessManagerChannel ml = channel(AppBuildMode.release);
      final List<ServerState> states = <ServerState>[];
      final StreamSubscription<ServerState> sub = ml.stateStream.listen(
        states.add,
      );
      addTearDown(sub.cancel);

      await ml
          .startServer(command: 'uvx', args: args)
          .catchError((Object _) {});
      await Future<void>.delayed(Duration.zero);

      expect(states.last, ServerState.error);
      expect(await ml.getServerState(), ServerState.error);
    });

    test('rien n\'est tué ni lancé', () async {
      await channel(
        AppBuildMode.release,
      ).startServer(command: 'uvx', args: args).catchError((Object _) {});

      expect(host.kills, isEmpty);
      expect(host.started, isEmpty);
    });

    test('un build de dev n\'est pas gêné : il prend 8100', () async {
      await channel(AppBuildMode.debug).startServer(command: 'uvx', args: args);

      expect(host.started, hasLength(1));
      expect(host.kills, isEmpty);
    });
  });
}
