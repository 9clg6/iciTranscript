import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Un processus tel que le système le voit (une ligne de `ps`).
final class RunningProcess {
  /// Cree un [RunningProcess].
  const RunningProcess({
    required this.pid,
    required this.startTime,
    required this.command,
  });

  /// PID.
  final int pid;

  /// Heure de démarrage telle que l'OS la donne (`ps -o lstart=`).
  final String startTime;

  /// Ligne de commande complète.
  final String command;
}

/// Un serveur lancé par l'app, noté dans le fichier d'état.
final class OwnedProcess {
  /// Cree un [OwnedProcess].
  const OwnedProcess({
    required this.role,
    required this.pid,
    required this.startTime,
    required this.command,
  });

  /// Rôle (transcription, diarization…), un processus par rôle.
  final String role;

  /// PID au lancement.
  final int pid;

  /// Heure de démarrage lue au lancement.
  final String startTime;

  /// Fin de la ligne de commande lancée (nom de l'exécutable + arguments).
  final String command;

  Map<String, Object> _toJson() => <String, Object>{
    'role': role,
    'pid': pid,
    'startTime': startTime,
    'command': command,
  };

  static OwnedProcess _fromJson(Map<String, dynamic> json) => OwnedProcess(
    role: json['role'] as String,
    pid: json['pid'] as int,
    startTime: json['startTime'] as String,
    command: json['command'] as String,
  );

  /// Même PID, même heure de démarrage, et la commande vue finit par celle
  /// lancée (un `exec` en chaîne, ex. `uvx` → `uv tool uvx`, garde la fin).
  bool isSameAs(RunningProcess running) =>
      running.pid == pid &&
      running.startTime == startTime &&
      running.command.endsWith(command);
}

/// Restes notés qui tournent encore avec la même identité : les seuls que
/// l'app a le droit d'arrêter au lancement.
List<OwnedProcess> leftoversToKill(
  List<OwnedProcess> recorded,
  List<RunningProcess> running,
) => <OwnedProcess>[
  for (final OwnedProcess p in recorded)
    if (running.any(p.isSameAs)) p,
];

/// Le port voulu est pris par un programme que l'app n'a pas lancé.
final class PortInUseException implements Exception {
  /// Cree une [PortInUseException].
  const PortInUseException(this.port);

  /// Port occupé.
  final int port;

  /// Message (anglais, pour les journaux ; l'UI a sa clé de traduction).
  String get message => 'port $port is used by another program';

  @override
  String toString() => 'PortInUseException: $message';
}

/// Lancer, lister, signaler les processus, sonder un port ou une URL. Seule
/// porte vers l'OS ; les tests la remplacent par un faux.
abstract interface class ProcessHost {
  /// Lance un processus.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  });

  /// Table des processus vivants.
  Future<List<RunningProcess>> running();

  /// Envoie [signal] au processus [pid] (et à son groupe s'il le mène).
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]);

  /// Vrai si rien n'écoute sur 127.0.0.1:[port].
  Future<bool> isPortFree(int port);

  /// Vrai si [url] répond 200.
  Future<bool> isHealthy(Uri url);
}

/// Fichier d'état des serveurs lancés, dans le dossier de données de l'app
/// (un build de dev et la release ont chacun le leur).
String ownedProcessesFile() => '${appDataDirectory()}/servers.json';

/// Serveurs lancés par l'app : note PID + identité de chacun, les arrête
/// (SIGTERM, puis SIGKILL après [grace]) et nettoie au lancement les restes
/// d'un arrêt brutal. Ne touche jamais un processus qu'elle n'a pas lancé.
final class OwnedProcessRegistry {
  /// Cree un [OwnedProcessRegistry].
  OwnedProcessRegistry({required ProcessHost host, required String stateFile})
    : _host = host,
      _stateFile = File(stateFile);

  /// Délai entre SIGTERM et SIGKILL.
  static const Duration grace = Duration(seconds: 5);

  final ProcessHost _host;
  final File _stateFile;
  final Log _log = Log.named('OwnedProcessRegistry');
  final Map<String, ({Process process, int port})> _live =
      <String, ({Process process, int port})>{};

  /// Lance [executable] pour [role] sur [port] et le note. Lève
  /// [PortInUseException] si un autre programme tient déjà [port] : rien
  /// n'est alors tué, lancé ni noté.
  Future<Process> start(
    String role,
    String executable,
    List<String> arguments, {
    required int port,
    Map<String, String>? environment,
  }) async {
    if (!await _host.isPortFree(port)) throw PortInUseException(port);
    final Process process = await _host.start(
      executable,
      arguments,
      environment: environment,
    );
    _live[role] = (process: process, port: port);
    await _record(
      role,
      process.pid,
      <String>[executable.split('/').last, ...arguments].join(' '),
    );
    unawaited(
      process.exitCode.then((_) {
        if (identical(_live[role]?.process, process)) {
          _live.remove(role);
          _forget(role);
        }
      }),
    );
    return process;
  }

  /// Arrête le serveur de [role] lancé par ce registre ; sinon ne fait rien.
  /// Attend ensuite (borné) que son port se libère.
  Future<void> stop(String role) async {
    final ({Process process, int port})? live = _live.remove(role);
    if (live == null) return;
    final Process process = live.process;
    _host.kill(process.pid);
    if (!await _exited(process)) {
      _log.warning('$role ignore SIGTERM, SIGKILL (pid ${process.pid})');
      _host.kill(process.pid, ProcessSignal.sigkill);
      await _exited(process);
    }
    _forget(role);
    for (int i = 0; i < 20 && !await _host.isPortFree(live.port); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Sonde de santé, par l'hôte.
  Future<bool> isHealthy(Uri url) => _host.isHealthy(url);

  /// Au lancement : arrête les restes notés qui ont encore la même identité.
  /// Ne lève jamais.
  Future<void> cleanUpLeftovers() async {
    final List<OwnedProcess> recorded;
    try {
      recorded = _read();
    } on Object catch (e) {
      _log.warning('Fichier d\'état illisible, rien nettoyé: $e');
      return;
    }
    if (recorded.isEmpty) return;
    final List<RunningProcess> running;
    try {
      running = await _host.running();
    } on Object catch (e) {
      _log.warning('Table des processus illisible, rien nettoyé: $e');
      return;
    }
    for (final OwnedProcess p in leftoversToKill(recorded, running)) {
      _log.info('Reste du lancement précédent: ${p.role} (pid ${p.pid})');
      await _terminateLeftover(p);
    }
    _write(<OwnedProcess>[
      for (final OwnedProcess p in _readOrEmpty())
        if (_live.containsKey(p.role) && _live[p.role]!.process.pid == p.pid) p,
    ]);
  }

  // ---------------------------------------------------------------------------

  Future<bool> _exited(Process process) => process.exitCode
      .then((_) => true)
      .timeout(grace, onTimeout: () => false);

  Future<void> _terminateLeftover(OwnedProcess p) async {
    _host.kill(p.pid);
    final Stopwatch watch = Stopwatch()..start();
    while (true) {
      final List<RunningProcess> running;
      try {
        running = await _host.running();
      } on Object {
        return;
      }
      if (!running.any(p.isSameAs)) return;
      if (watch.elapsed >= grace) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _host.kill(p.pid, ProcessSignal.sigkill);
  }

  Future<void> _record(String role, int pid, String command) async {
    final List<RunningProcess> running;
    try {
      running = await _host.running();
    } on Object catch (e) {
      _log.warning('Identité de $role (pid $pid) illisible, non notée: $e');
      return;
    }
    final RunningProcess? seen = running
        .where((RunningProcess r) => r.pid == pid)
        .firstOrNull;
    if (seen == null) return; // Déjà terminé : rien à nettoyer plus tard.
    _write(<OwnedProcess>[
      for (final OwnedProcess p in _readOrEmpty())
        if (p.role != role) p,
      OwnedProcess(
        role: role,
        pid: pid,
        startTime: seen.startTime,
        command: command,
      ),
    ]);
  }

  void _forget(String role) => _write(<OwnedProcess>[
    for (final OwnedProcess p in _readOrEmpty())
      if (p.role != role) p,
  ]);

  List<OwnedProcess> _read() {
    if (!_stateFile.existsSync()) return <OwnedProcess>[];
    final List<dynamic> json =
        jsonDecode(_stateFile.readAsStringSync()) as List<dynamic>;
    return <OwnedProcess>[
      for (final dynamic e in json)
        OwnedProcess._fromJson(e as Map<String, dynamic>),
    ];
  }

  List<OwnedProcess> _readOrEmpty() {
    try {
      return _read();
    } on Object {
      return <OwnedProcess>[];
    }
  }

  // Écriture atomique (fichier temporaire puis renommage) ; un seul
  // écrivain : ce registre, une instance par app.
  void _write(List<OwnedProcess> entries) {
    try {
      if (entries.isEmpty) {
        if (_stateFile.existsSync()) _stateFile.deleteSync();
        return;
      }
      _stateFile.parent.createSync(recursive: true);
      final File tmp = File('${_stateFile.path}.tmp');
      tmp.writeAsStringSync(
        jsonEncode(<Object>[for (final OwnedProcess p in entries) p._toJson()]),
        flush: true,
      );
      tmp.renameSync(_stateFile.path);
    } on FileSystemException catch (e) {
      _log.warning('Fichier d\'état non écrit: $e');
    }
  }
}
