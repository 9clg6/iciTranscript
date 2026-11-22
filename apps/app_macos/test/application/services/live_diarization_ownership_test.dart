import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_diarization.service.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

import '../../helpers/process_host_fakes.dart';

/// Le serveur des interlocuteurs en direct (nemotron_diar_mlx.server) :
/// lancé sur le port du lancement (8001 en release, 8101 sur données de dev),
/// sondé sur ce même port, arrêté sans tuer le serveur d'une autre app.
///
/// La sonde de santé reste fausse : le service n'ouvre jamais sa WebSocket,
/// donc aucun vrai port n'est touché.
void main() {
  const RunningProcess installedServer = RunningProcess(
    pid: 778,
    startTime: 'Sun Nov 22 08:00:01 2026',
    command:
        '/Users/someone/.local/bin/uv run python -m nemotron_diar_mlx.server '
        '--port 8001',
  );

  late Directory dir;
  late FakeProcessHost host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('live_diarization_test_');
    host = FakeProcessHost()
      ..addForeign(installedServer)
      ..healthy = false;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  LiveDiarizationService service(AppBuildMode mode) => LiveDiarizationService(
    processes: OwnedProcessRegistry(
      host: host,
      stateFile: '${dir.path}/servers.json',
    ),
    ports: resolveServerPorts(const <String, String>{
      'HOME': '/Users/someone',
    }, buildMode: mode),
  );

  /// Lance [diarization] jusqu'à la première sonde de santé, puis l'arrête.
  Future<void> startThenStop(LiveDiarizationService diarization) async {
    final Future<void> starting = diarization.start();
    await eventually(() => host.healthChecks.isNotEmpty);
    await diarization.stop();
    await expectLater(starting, throwsA(anything));
  }

  for (final (AppBuildMode mode, int port) in <(AppBuildMode, int)>[
    (AppBuildMode.release, 8001),
    (AppBuildMode.debug, 8101),
  ]) {
    test('${mode.name} : lancé avec --port $port, sondé sur $port', () async {
      await startThenStop(service(mode));

      expect(host.started, hasLength(1));
      expect(host.commandLine(0), contains('--port $port'));
      expect(host.healthChecks.toSet(), <Uri>{
        Uri.parse('http://127.0.0.1:$port/health'),
      });
    });
  }

  test('démarrer puis arrêter ne tue que le serveur lancé', () async {
    await startThenStop(service(AppBuildMode.debug));

    expect(host.killedPids, <int>{host.processes.keys.single});
    expect(host.table, contains(installedServer.pid));
  });

  test('arrêter sans avoir démarré ne tue rien', () async {
    await service(AppBuildMode.release).stop();

    expect(host.kills, isEmpty);
  });

  test(
    'port 8001 pris par un autre programme : erreur claire, rien tué',
    () async {
      host.busyPorts.add(8001);

      await expectLater(
        service(AppBuildMode.release).start(),
        throwsA(
          isA<PortInUseException>()
              .having((PortInUseException e) => e.port, 'port', 8001)
              .having(
                (PortInUseException e) => e.toString(),
                'message',
                contains('port 8001 is used by another program'),
              ),
        ),
      );
      expect(host.kills, isEmpty);
      expect(host.started, isEmpty);
    },
  );
}
