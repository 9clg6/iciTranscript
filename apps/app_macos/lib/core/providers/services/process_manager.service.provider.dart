import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_manager.service.provider.g.dart';

/// Wrapper applicatif autour de [ProcessManagerChannel].
///
/// Fournit une API simplifiee pour demarrer/arreter le serveur ML
/// et expose des streams types pour l'etat du serveur et les logs.
final class ProcessManagerService {
  /// Cree une instance de [ProcessManagerService].
  ProcessManagerService({required ProcessManagerChannel channel})
    : _channel = channel;

  final ProcessManagerChannel _channel;
  final Log _log = Log.named('ProcessManagerService');

  /// Stream de l'etat du serveur ML.
  Stream<ServerState> get stateStream => _channel.stateStream;

  /// Stream des logs du serveur ML.
  Stream<String> get logsStream => _channel.logsStream;

  /// Demarre le serveur ML avec le binaire a l'emplacement donne.
  Future<void> startServer({
    required String command,
    List<String> args = const <String>[],
    String? readyPattern,
  }) async {
    _log.info('Demarrage du serveur ML : $command');
    await _channel.startServer(
      command: command,
      args: args,
      readyPattern: readyPattern,
    );
  }

  /// Arrete le serveur ML.
  Future<void> stopServer() async {
    _log.info('Arret du serveur ML');
    await _channel.stopServer();
  }

  /// Indique si le serveur ML est en cours d'execution.
  Future<bool> isServerRunning() {
    return _channel.isServerRunning();
  }

  /// Etat courant du serveur ML.
  Future<ServerState> getServerState() {
    return _channel.getServerState();
  }
}

/// Provider singleton pour [ProcessManagerService].
///
/// Wrape le [ProcessManagerChannel] pour fournir une API
/// de plus haut niveau pour le cycle de vie du serveur ML.
@Riverpod(keepAlive: true)
ProcessManagerService processManagerService(Ref ref) {
  final ProcessManagerChannel channel = ref.watch(
    processManagerChannelProvider,
  );
  return ProcessManagerService(channel: channel);
}
