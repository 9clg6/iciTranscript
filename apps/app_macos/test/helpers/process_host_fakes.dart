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
///
/// Un serveur lancé mène son propre groupe (groupe = PID du meneur) sauf si
/// [startGroupId] est fixé. [addChild] ajoute un enfant dans le groupe d'un
/// meneur (ex. `uvx` → `python`, qui tient le port) avec sa propre réaction
/// à SIGTERM.
final class FakeProcessHost implements ProcessHost {
  FakeProcessHost({this.firstPid = 5000, this.appGroupId = 400});

  final int firstPid;
  late int _nextPid = firstPid;

  /// Groupe de processus de l'app elle-même.
  @override
  final int appGroupId;

  /// Groupe donné aux processus lancés ; null : leur propre groupe.
  int? startGroupId;

  /// Table des processus vivants, par PID (ce que verrait `ps`).
  final Map<int, RunningProcess> table = <int, RunningProcess>{};

  /// Ports déjà pris par un autre programme.
  final Set<int> busyPorts = <int>{};

  /// Port tenu par un PID : libre dès que ce PID ne tourne plus.
  final Map<int, int> portHolders = <int, int>{};

  /// Réponse des sondes `/health`.
  bool healthy = true;

  /// Les processus lancés ignorent SIGTERM (seul SIGKILL les arrête).
  bool ignoreSigterm = false;

  /// La lecture de la table des processus échoue.
  bool failSnapshots = false;

  /// Réaction à SIGTERM par PID : absent = sortie immédiate ; durée = sortie
  /// après ce délai ; null = ignoré.
  final Map<int, Duration?> termDelays = <int, Duration?>{};

  final List<({String executable, List<String> arguments})> started =
      <({String executable, List<String> arguments})>[];
  final Map<int, FakeProcess> processes = <int, FakeProcess>{};
  final List<({int pid, ProcessSignal signal})> kills =
      <({int pid, ProcessSignal signal})>[];
  final List<({int groupId, ProcessSignal signal})> groupKills =
      <({int groupId, ProcessSignal signal})>[];
  final List<Uri> healthChecks = <Uri>[];
  int snapshots = 0;

  final Set<int> _reached = <int>{};

  /// Ligne de commande complète du lancement [index] (exécutable compris),
  /// pour ne pas dépendre d'un éventuel `/bin/sh -c`.
  String commandLine(int index) => <String>[
    started[index].executable,
    ...started[index].arguments,
  ].join(' ');

  /// PIDs ayant reçu au moins un signal, seul ou par leur groupe.
  Set<int> get killedPids => <int>{...kills.map((k) => k.pid), ..._reached};

  /// Groupes signalés.
  Set<int> get killedGroups => groupKills.map((k) => k.groupId).toSet();

  /// Membres vivants du groupe [groupId].
  List<int> members(int groupId) => <int>[
    for (final RunningProcess p in table.values)
      if (p.groupId == groupId) p.pid,
  ];

  /// Heure de démarrage `ps -o lstart=` à [offset] secondes de 10:01:00.
  static String lstart(int offset) {
    final int s = 60 + offset;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Sun Nov 22 10:${two(s ~/ 60)}:${two(s % 60)} 2026';
  }

  /// Ajoute à la table un processus qui n'a pas été lancé par ce faux (un
  /// autre programme, ou un reste d'un lancement précédent).
  void addForeign(RunningProcess process) => table[process.pid] = process;

  /// Enfant de [leaderPid], dans son groupe, démarré une seconde après lui.
  /// [termDelay] : null = ignore SIGTERM ; sinon sort après ce délai.
  int addChild(
    int leaderPid, {
    required String command,
    Duration? termDelay = Duration.zero,
    int? holdsPort,
  }) {
    final RunningProcess leader = table[leaderPid]!;
    final int child = _nextPid++;
    table[child] = RunningProcess(
      pid: child,
      groupId: leader.groupId,
      startTime: lstart(child - firstPid + 1),
      command: command,
    );
    termDelays[child] = termDelay;
    if (holdsPort != null) portHolders[holdsPort] = child;
    return child;
  }

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
      groupId: startGroupId ?? pid,
      startTime: lstart(pid - firstPid),
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
    _deliver(pid, signal);
    return alive;
  }

  @override
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]) {
    groupKills.add((groupId: groupId, signal: signal));
    final List<int> targets = members(groupId);
    for (final int pid in targets) {
      _deliver(pid, signal);
    }
    return targets.isNotEmpty;
  }

  void _deliver(int pid, ProcessSignal signal) {
    if (!table.containsKey(pid)) return;
    _reached.add(pid);
    if (signal == ProcessSignal.sigkill) return _die(pid);
    if (processes.containsKey(pid) && !termDelays.containsKey(pid)) {
      if (!ignoreSigterm) _die(pid);
      return;
    }
    if (!termDelays.containsKey(pid)) return _die(pid);
    final Duration? delay = termDelays[pid];
    if (delay == null) return;
    if (delay == Duration.zero) return _die(pid);
    Timer(delay, () => _die(pid));
  }

  void _die(int pid) {
    table.remove(pid);
    processes[pid]?.exit(-15);
  }

  @override
  Future<bool> isPortFree(int port) async {
    if (busyPorts.contains(port)) return false;
    final int? holder = portHolders[port];
    return holder == null || !table.containsKey(holder);
  }

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
