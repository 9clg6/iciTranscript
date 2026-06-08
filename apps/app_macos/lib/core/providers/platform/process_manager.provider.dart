import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_manager.provider.g.dart';

/// Provider singleton pour [ProcessManagerChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la gestion
/// du processus voxmlx-serve (serveur ML de transcription).
@Riverpod(keepAlive: true)
ProcessManagerChannel processManagerChannel(Ref ref) {
  final ProcessManagerChannel channel = ProcessManagerChannel();
  ref.onDispose(channel.dispose);
  return channel;
}
