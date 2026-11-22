import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';

import '../../helpers/process_host_fakes.dart';

/// Au lancement, l'app nettoie les serveurs qu'elle avait lancés et qu'un
/// arrêt brutal a laissés : seulement ceux notés dans son fichier d'état
/// dont le PID a encore la même identité. Celui d'une autre app (l'app
/// installée à côté d'un build de dev) n'est jamais touché. Un échec du
/// nettoyage ne bloque pas le lancement.
void main() {
  const RunningProcess installedServer = RunningProcess(
    pid: 777,
    startTime: 'Sun Nov 22 08:00:00 2026',
    command: '/Users/someone/.local/bin/uvx voxmlx-serve --port 8000',
  );

  late Directory dir;
  late String stateFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kernel_leftovers_test_');
    stateFile = '${dir.path}/servers.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> launchApp(FakeProcessHost host) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(
          AppDatabase(NativeDatabase.memory()),
        ),
        ownedProcessRegistryProvider.overrideWithValue(
          OwnedProcessRegistry(host: host, stateFile: stateFile),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(kernelProvider.future);
  }

  test('un serveur laissé par le lancement précédent est arrêté', () async {
    final FakeProcessHost previous = FakeProcessHost();
    final Process leftover = await OwnedProcessRegistry(
      host: previous,
      stateFile: stateFile,
    ).start('transcription', 'uvx', <String>['voxmlx-serve'], port: 8100);

    final FakeProcessHost host = FakeProcessHost(firstPid: 9000)
      ..table.addAll(previous.table)
      ..addForeign(installedServer);
    await launchApp(host);

    expect(host.killedPids, <int>{leftover.pid});
  });

  test(
    'sans reste noté, le serveur de l\'app installée n\'est pas touché',
    () async {
      final FakeProcessHost host = FakeProcessHost()
        ..addForeign(installedServer);

      await launchApp(host);

      expect(host.kills, isEmpty);
    },
  );

  test('nettoyage en échec : le lancement continue', () async {
    await OwnedProcessRegistry(
      host: FakeProcessHost(),
      stateFile: stateFile,
    ).start('transcription', 'uvx', <String>['voxmlx-serve'], port: 8100);
    final FakeProcessHost host = FakeProcessHost()..failSnapshots = true;

    await expectLater(launchApp(host), completes);
    expect(host.kills, isEmpty);
  });
}
