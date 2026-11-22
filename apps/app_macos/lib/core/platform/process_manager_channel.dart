import 'dart:async';
import 'dart:io';

import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';
import 'package:ici_transcript/core/platform/system_process_host.dart';

/// Gestionnaire du processus voxmlx-serve.
///
/// Lance, surveille et arrete le serveur ML via [OwnedProcessRegistry] :
/// l'app n'arrete que le serveur qu'elle a lance, sur le port du lancement.
class ProcessManagerChannel {
  /// Cree une instance de [ProcessManagerChannel].
  ProcessManagerChannel({OwnedProcessRegistry? processes, ServerPorts? ports})
    : _processes =
          processes ??
          OwnedProcessRegistry(
            host: const SystemProcessHost(),
            stateFile: ownedProcessesFile(),
          ),
      _ports = ports ?? serverPorts();

  static const String _role = 'transcription';

  final OwnedProcessRegistry _processes;
  final ServerPorts _ports;

  final Log _log = Log.named('ProcessManagerChannel');

  Process? _serverProcess;
  ServerState _currentState = ServerState.stopped;

  final StreamController<ServerState> _stateController =
      StreamController<ServerState>.broadcast();
  final StreamController<String> _logsController =
      StreamController<String>.broadcast();

  /// Stream de l'etat du serveur ML.
  Stream<ServerState> get stateStream => _stateController.stream;

  /// Stream des logs du serveur (stdout + stderr).
  Stream<String> get logsStream => _logsController.stream;

  /// Demarre le serveur ML sur le port du lancement ([ServerPorts]).
  ///
  /// [command] — commande a lancer (ex: 'uvx').
  /// [args] — arguments de la commande (`--port` est ajoute ici).
  /// [readyPattern] — pattern dans stdout qui indique que le serveur est pret.
  ///
  /// Leve [PortInUseException] si un autre programme tient le port : il
  /// n'est jamais tue.
  Future<void> startServer({
    required String command,
    List<String> args = const <String>[],
    String? readyPattern,
  }) async {
    if (_serverProcess != null) {
      _log.warning('Serveur deja en cours, arret prealable');
      await stopServer();
    }

    _setState(ServerState.starting);

    // Resoudre le chemin complet de la commande
    final String resolvedCommand = await _resolveCommand(command);
    final List<String> fullArgs = <String>[
      ...args,
      '--port',
      '${_ports.transcription}',
    ];
    _log.info('Lancement: $resolvedCommand ${fullArgs.join(' ')}');

    try {
      final Process serverProcess = await _processes.start(
        _role,
        resolvedCommand,
        fullArgs,
        port: _ports.transcription,
        environment: <String, String>{
          'HOME': Platform.environment['HOME'] ?? '/Users/unknown',
          'PATH': _extendedPath(),
          'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
        },
      );
      _serverProcess = serverProcess;

      final Completer<void> readyCompleter = Completer<void>();
      bool isReady = false;
      // Dernières lignes stderr, remontées si le serveur meurt avant d'être
      // prêt (ex: échec d'installation uv) — sinon l'erreur reste invisible.
      final List<String> recentStderr = <String>[];

      unawaited(
        _waitForServerHealth(serverProcess).then((bool healthy) {
          if (healthy &&
              identical(_serverProcess, serverProcess) &&
              !readyCompleter.isCompleted) {
            isReady = true;
            _setState(ServerState.ready);
            readyCompleter.complete();
          }
        }),
      );

      // Ecouter stdout
      serverProcess.stdout.transform(const SystemEncoding().decoder).listen((
        String data,
      ) {
        for (final String line in data.split('\n')) {
          if (line.trim().isEmpty) continue;
          _logsController.add('[stdout] $line');
          _log.debug('[stdout] $line');

          // Le fork émet le marqueur avant que la socket Uvicorn soit
          // nécessairement liée. Le healthcheck HTTP reste l'autorité.
          if (!isReady && readyPattern != null && line.contains(readyPattern)) {
            _log.debug('Marqueur ready observé: $readyPattern');
          }
        }
      });

      // Ecouter stderr
      serverProcess.stderr.transform(const SystemEncoding().decoder).listen((
        String data,
      ) {
        for (final String line in data.split('\n')) {
          if (line.trim().isEmpty) continue;
          _logsController.add('[stderr] $line');
          _log.debug('[stderr] $line');
          recentStderr.add(line);
          if (recentStderr.length > 20) recentStderr.removeAt(0);

          // Uvicorn écrit dans stderr, mais seul GET /health évite une course
          // avec la connexion WebSocket qui suit immédiatement.
          if (!isReady && readyPattern != null && line.contains(readyPattern)) {
            _log.debug('Marqueur ready observé: $readyPattern');
          }
        }
      });

      // Detecter la fin du processus
      serverProcess.exitCode.then((int code) {
        if (!identical(_serverProcess, serverProcess)) return;
        _log.info('Serveur arrete avec code: $code');
        _serverProcess = null;
        if (!readyCompleter.isCompleted) {
          _log.error(
            'Le serveur ML s\'est arrêté avant d\'être prêt ($code):\n'
            '${recentStderr.join('\n')}',
          );
          readyCompleter.completeError(
            StateError(
              'Le serveur ML s\'est arrêté avant d\'être prêt ($code)',
            ),
          );
        }
        if (_currentState != ServerState.stopped) {
          _setState(code == 0 ? ServerState.stopped : ServerState.error);
        }
      });

      // Le premier lancement peut télécharger le modèle (~2,3 Go), d'où le
      // timeout large. Un échec n'est plus masqué par un faux état "ready".
      await readyCompleter.future.timeout(const Duration(seconds: 600));
    } catch (e) {
      _log.error('Erreur lancement serveur', e);
      await stopServer();
      _setState(ServerState.error);
      rethrow;
    }
  }

  /// Arrete le serveur ML lance par l'app (et lui seul).
  Future<void> stopServer() async {
    final Process? process = _serverProcess;
    if (process == null) {
      _setState(ServerState.stopped);
      return;
    }

    // SIGTERM au groupe lance, SIGKILL apres un delai : jamais par nom.
    _log.info('Arret du serveur (pid ${process.pid})');
    _serverProcess = null;
    await _processes.stop(_role);

    _serverProcess = null;
    _setState(ServerState.stopped);
  }

  /// Verifie si `uvx` est disponible sur le PATH.
  ///
  /// Retourne [true] si la commande est trouvee, [false] sinon.
  Future<bool> checkUvxAvailable() async {
    final String extPath = _extendedPath();
    for (final String dir in extPath.split(':')) {
      if (dir.isEmpty) continue;
      final String candidate = '$dir/uvx';
      if (await File(candidate).exists()) {
        _log.info('uvx trouve: $candidate');
        return true;
      }
    }
    _log.warning('uvx non trouve dans le PATH etendu');
    return false;
  }

  /// Installe `uv` via le script officiel d'Astral.
  ///
  /// Retourne [true] si l'installation a reussi, [false] sinon.
  Future<bool> installUv() async {
    _log.info('Installation de uv via astral.sh...');
    try {
      final ProcessResult result = await Process.run(
        '/bin/sh',
        <String>['-c', 'curl -LsSf https://astral.sh/uv/install.sh | sh'],
        environment: <String, String>{
          'HOME': Platform.environment['HOME'] ?? '/Users/unknown',
          'PATH': _extendedPath(),
        },
      ).timeout(const Duration(seconds: 120));

      final bool success = result.exitCode == 0;
      if (success) {
        _log.info('uv installe avec succes');
      } else {
        _log.error('Echec installation uv', result.stderr);
      }
      return success;
    } on Exception catch (e) {
      _log.error('Erreur installation uv', e);
      return false;
    }
  }

  /// Indique si le serveur est en cours d'execution.
  Future<bool> isServerRunning() async {
    return _serverProcess != null;
  }

  /// Etat courant du serveur.
  Future<ServerState> getServerState() async {
    return _currentState;
  }

  /// Libere les ressources.
  Future<void> dispose() async {
    await stopServer();
    await _stateController.close();
    await _logsController.close();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _setState(ServerState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  Future<bool> _waitForServerHealth(Process expectedProcess) async {
    final Stopwatch timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 600)) {
      if (!identical(_serverProcess, expectedProcess)) return false;
      // Le modèle charge ou la socket n'est pas encore liée.
      if (await _processes.isHealthy(_ports.transcriptionHealth)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /// Construit un PATH etendu incluant les emplacements courants de uvx.
  String _extendedPath() {
    final String home = Platform.environment['HOME'] ?? '/Users/unknown';
    final String currentPath = Platform.environment['PATH'] ?? '';
    return <String>[
      '$home/.local/bin',
      '$home/.cargo/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      currentPath,
    ].join(':');
  }

  /// Resout le chemin complet d'une commande.
  Future<String> _resolveCommand(String command) async {
    // Si c'est deja un chemin absolu, le retourner
    if (command.startsWith('/')) return command;

    // Chercher dans le PATH etendu
    final String extPath = _extendedPath();
    for (final String dir in extPath.split(':')) {
      final String candidate = '$dir/$command';
      if (await File(candidate).exists()) {
        _log.info('Commande trouvee: $candidate');
        return candidate;
      }
    }

    // Fallback : retourner la commande telle quelle
    _log.warning(
      'Commande "$command" non trouvee dans le PATH, '
      'tentative directe',
    );
    return command;
  }
}
