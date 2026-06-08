import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'uvx_available.provider.g.dart';

/// Vérifie si `uvx` est disponible sur le PATH au démarrage.
///
/// Utilisé pour décider d'afficher ou non l'écran d'onboarding.
@Riverpod(keepAlive: true)
Future<bool> uvxAvailable(Ref ref) async {
  final channel = ref.read(processManagerChannelProvider);
  return channel.checkUvxAvailable();
}
