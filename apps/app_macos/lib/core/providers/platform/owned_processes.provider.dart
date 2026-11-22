import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';
import 'package:ici_transcript/core/platform/system_process_host.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'owned_processes.provider.g.dart';

/// Seul registre des serveurs lancés par l'app (un seul écrivain du fichier
/// d'état).
@Riverpod(keepAlive: true)
OwnedProcessRegistry ownedProcessRegistry(Ref ref) => OwnedProcessRegistry(
  host: const SystemProcessHost(),
  stateFile: ownedProcessesFile(),
);

/// Ports des serveurs pour ce lancement (8100/8101 sur données de dev).
@Riverpod(keepAlive: true)
ServerPorts launchServerPorts(Ref ref) => serverPorts();
