import 'dart:async';
import 'dart:io';

import 'package:ici_transcript/core/platform/owned_processes.dart';

// Système factice : aucun vrai processus lancé ni tué, aucun vrai port ouvert
// ou sondé. Le test décrit la table des processus et les ports occupés ; le
// faux enregistre chaque lancement, chaque signal et chaque sonde de santé.

/// Processus factice rendu par [FakeProcessHost.start].
final class FakeProcess implements Process {
  FakeProcess._(this.pid, this._host);

  @override
  final int pid;
  final FakeProcessHost _host;
  final Completer<int> _exit = Completer<int>();

  /// Le processus se termine de lui-même avec [code].
  void exit(int code) {
    _host.table.remove(pid);
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  final Stream<List<int>> stdout = const Stream<List<int>>.empty();

  @override
  final Stream<List<int>> stderr = const Stream<List<int>>.empty();

  @override
  late final IOSink stdin = IOSink(StreamController<List<int>>().sink);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _host.kill(pid, signal);
}

/// Hôte de processus factice.
final class FakeProcessHost implements ProcessHost {
  FakeProcessHost({this.firstPid = 5000});

  final int firstPid;
  late int _nextPid = firstPid;

  /// Table des processus vivants, par PID (ce que verrait `ps`).
  final Map<int, RunningProcess> table = <int, RunningProcess>{};

  /// Ports déjà pris par un autre programme.
  final Set<int> busyPorts = <int>{};

  /// Réponse des sondes `/health`.
  bool healthy = true;

  /// Les processus lancés ignorent SIGTERM (seul SIGKILL les arrête).
  bool ignoreSigterm = false;

  /// La lecture de la table des processus échoue.
  bool failSnapshots = false;

  final List<({String executable, List<String> arguments})> started =
      <({String executable, List<String> arguments})>[];
  final Map<int, FakeProcess> processes = <int, FakeProcess>{};
  final List<({int pid, ProcessSignal signal})> kills =
      <({int pid, ProcessSignal signal})>[];
  final List<Uri> healthChecks = <Uri>[];
  int snapshots = 0;

  /// Ligne de commande complète du lancement [index] (exécutable compris),
  /// pour ne pas dépendre d'un éventuel `/bin/sh -c`.
  String commandLine(int index) => <String>[
    started[index].executable,
    ...started[index].arguments,
  ].join(' ');

  /// PIDs ayant reçu au moins un signal.
  Set<int> get killedPids => kills.map((k) => k.pid).toSet();

  /// Ajoute à la table un processus qui n'a pas été lancé par ce faux (un
  /// autre programme, ou un reste d'un lancement précédent).
  void addForeign(RunningProcess process) => table[process.pid] = process;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final int pid = _nextPid++;
    started.add((executable: executable, arguments: arguments));
    table[pid] = RunningProcess(
      pid: pid,
      startTime: 'Sun Nov 22 10:00:${pid % 60} 2026',
      command: <String>[executable, ...arguments].join(' '),
    );
    final FakeProcess process = FakeProcess._(pid, this);
    processes[pid] = process;
    return process;
  }

  @override
  Future<List<RunningProcess>> running() async {
    snapshots++;
    if (failSnapshots) throw const ProcessException('ps', <String>[], 'boom');
    return table.values.toList();
  }

  @override
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    kills.add((pid: pid, signal: signal));
    final bool alive = table.containsKey(pid);
    if (signal == ProcessSignal.sigkill || !ignoreSigterm) {
      table.remove(pid);
      processes[pid]?.exit(-15);
    }
    return alive;
  }

  @override
  Future<bool> isPortFree(int port) async => !busyPorts.contains(port);

  @override
  Future<bool> isHealthy(Uri url) async {
    healthChecks.add(url);
    return healthy;
  }
}

/// Attend (au plus ~2 s de vrai temps) que [condition] devienne vraie.
Future<void> eventually(bool Function() condition) async {
  for (int i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
