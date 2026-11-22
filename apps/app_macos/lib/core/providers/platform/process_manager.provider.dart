import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_manager.provider.g.dart';

/// Provider singleton pour [ProcessManagerChannel].
///
/// Gere le processus voxmlx-serve (serveur ML de transcription), lance par
/// le registre partage sur le port du lancement.
@Riverpod(keepAlive: true)
ProcessManagerChannel processManagerChannel(Ref ref) {
  final ProcessManagerChannel channel = ProcessManagerChannel(
    processes: ref.watch(ownedProcessRegistryProvider),
    ports: ref.watch(launchServerPortsProvider),
  );
  ref.onDispose(channel.dispose);
  return channel;
}
