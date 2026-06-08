import 'dart:async';
import 'dart:io';

import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';

/// Gestionnaire du processus voxmlx-serve.
///
/// Lance, surveille et arrete le serveur ML directement via [dart:io Process].
/// Pas besoin de platform channel Swift — Dart gere les processus natifs.
class ProcessManagerChannel {
  /// Cree une instance de [ProcessManagerChannel].
  ProcessManagerChannel();

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

  /// Demarre le serveur ML.
  ///
  /// [command] — commande a lancer (ex: 'uvx').
  /// [args] — arguments de la commande.
  /// [readyPattern] — pattern dans stdout qui indique que le serveur est pret.
  /// Port sur lequel le serveur ML ecoute (par defaut 8000).
  static const int _serverPort = 8000;

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

    // Nettoyer le port au cas ou un ancien processus traine
    await _killProcessOnPort(_serverPort);

    // Resoudre le chemin complet de la commande
    final String resolvedCommand = await _resolveCommand(command);
    _log.info('Lancement: $resolvedCommand ${args.join(' ')}');

    try {
      // Lancer via /bin/sh pour heriter d'un environnement shell complet
      // et eviter les crashes Process.start sur macOS Flutter
      final String fullCommand =
          <String>[resolvedCommand, ...args].map((String a) {
        // Echapper les arguments contenant des caracteres speciaux
        if (a.contains(' ') || a.contains('[') || a.contains(']')) {
          return "'$a'";
        }
        return a;
      }).join(' ');
      _log.info('Commande shell: $fullCommand');

      _serverProcess = await Process.start(
        '/bin/sh',
        <String>['-c', fullCommand],
        environment: <String, String>{
          'HOME': Platform.environment['HOME'] ?? '/Users/unknown',
          'PATH': _extendedPath(),
          'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
        },
        mode: ProcessStartMode.normal,
      );

      final Completer<void> readyCompleter = Completer<void>();
      bool isReady = false;

      // Ecouter stdout
      _serverProcess!.stdout.transform(const SystemEncoding().decoder).listen((
        String data,
      ) {
        for (final String line in data.split('\n')) {
          if (line.trim().isEmpty) continue;
          _logsController.add('[stdout] $line');
          _log.debug('[stdout] $line');

          // Detecter le signal "pret"
          if (!isReady && readyPattern != null && line.contains(readyPattern)) {
            isReady = true;
            _setState(ServerState.ready);
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
          }
        }
      });

      // Ecouter stderr
      _serverProcess!.stderr.transform(const SystemEncoding().decoder).listen((
        String data,
      ) {
        for (final String line in data.split('\n')) {
          if (line.trim().isEmpty) continue;
          _logsController.add('[stderr] $line');
          _log.debug('[stderr] $line');

          // Uvicorn ecrit dans stderr
          if (!isReady && readyPattern != null && line.contains(readyPattern)) {
            isReady = true;
            _setState(ServerState.ready);
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
          }
        }
      });

      // Detecter la fin du processus
      _serverProcess!.exitCode.then((int code) {
        _log.info('Serveur arrete avec code: $code');
        _serverProcess = null;
        if (_currentState != ServerState.stopped) {
          _setState(code == 0 ? ServerState.stopped : ServerState.error);
        }
      });

      // Attendre que le serveur soit pret (timeout 600s au premier lancement
      // uvx doit telecharger le package + modele ML ~2-4 GB)
      if (readyPattern != null) {
        await readyCompleter.future.timeout(
          const Duration(seconds: 600),
          onTimeout: () {
            // Si pas de signal ready apres 120s, on considere que c'est pret
            // (le serveur peut etre pret sans log specifique)
            if (!isReady) {
              _log.warning(
                'Timeout attente ready pattern "$readyPattern" apres 600s, '
                'on continue quand meme',
              );
              _setState(ServerState.ready);
            }
          },
        );
      } else {
        // Pas de pattern, attendre 3s et considerer pret
        await Future<void>.delayed(const Duration(seconds: 3));
        _setState(ServerState.ready);
      }
    } on Exception catch (e) {
      _log.error('Erreur lancement serveur', e);
      _setState(ServerState.error);
      rethrow;
    }
  }

  /// Arrete le serveur ML.
  ///
  /// Envoie SIGTERM, attend 5s, puis SIGKILL si necessaire.
  Future<void> stopServer() async {
    final Process? process = _serverProcess;
    if (process == null) {
      _setState(ServerState.stopped);
      return;
    }

    final int pid = process.pid;
    _log.info('Envoi SIGTERM au serveur (pid $pid)');
    process.kill(ProcessSignal.sigterm);

    // Attendre 5s pour un arret propre
    final bool exited = await process.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1)
        .then((int code) => code != -1)
        .catchError((_) => false);

    if (!exited) {
      _log.warning('SIGTERM ignore, envoi SIGKILL');
      process.kill(ProcessSignal.sigkill);
    }

    // On a lance `/bin/sh -c "uvx ..."`. Tuer le sh ne tue PAS les enfants
    // uvx/python (reparentes a launchd → orphelins qui gardent le port 8000
    // et bloquent le prochain demarrage). On nettoie donc tout voxmlx par
    // pattern. (Pas de kill par PGID : l'enfant partage le PGID de l'app.)
    await Process.run('/usr/bin/pkill', <String>['-9', '-f', 'voxmlx']);

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

  /// Tue tout processus ecoutant sur le port [port].
  ///
  /// Utilise `lsof` pour trouver le PID puis envoie SIGKILL.
  /// Silencieux si aucun processus n'occupe le port.
  Future<void> _killProcessOnPort(int port) async {
    try {
      final ProcessResult result = await Process.run(
        '/bin/sh',
        <String>['-c', 'lsof -ti :$port'],
      );
      final String output = (result.stdout as String).trim();

      // Tuer le PID qui ecoute le port (l'enfant python qui detient le socket).
      if (output.isNotEmpty) {
        for (final String pid in output.split('\n')) {
          final String trimmedPid = pid.trim();
          if (trimmedPid.isEmpty) continue;
          _log.warning('Port $port occupe par PID $trimmedPid, SIGKILL');
          await Process.run('/bin/kill', <String>['-9', trimmedPid]);
        }
      }

      // `uvx` (`uv tool uvx`) est un superviseur : tuer seulement l'enfant
      // python ne suffit pas, le parent relance le serveur et reprend le port.
      // On tue donc tout processus voxmlx par pattern. NB : on ne peut PAS
      // tuer par groupe de processus (kill -9 -PGID) car l'enfant partage le
      // PGID de l'app Flutter → cela tuerait l'app elle-meme. Le pattern
      // "voxmlx" ne matche jamais le binaire de l'app.
      await Process.run('/usr/bin/pkill', <String>['-9', '-f', 'voxmlx']);

      // Laisser le temps au port de se liberer
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } on Exception catch (e) {
      _log.warning('Impossible de nettoyer le port $port: $e');
    }
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
