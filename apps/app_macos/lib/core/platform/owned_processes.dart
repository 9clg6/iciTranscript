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
    this.groupId = 0,
    required this.startTime,
    required this.command,
  });

  /// PID.
  final int pid;

  /// Groupe de processus (0 : inconnu).
  final int groupId;

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
    this.groupId = 0,
    required this.startTime,
    required this.command,
  });

  /// Rôle (transcription, diarization…), un processus par rôle.
  final String role;

  /// PID du meneur au lancement.
  final int pid;

  /// Groupe lu au lancement (0 : inconnu, jamais signalé comme groupe).
  final int groupId;

  /// Heure de démarrage lue au lancement.
  final String startTime;

  /// Fin de la ligne de commande lancée (nom de l'exécutable + arguments).
  final String command;

  Map<String, Object> _toJson() => <String, Object>{
    'role': role,
    'pid': pid,
    'groupId': groupId,
    'startTime': startTime,
    'command': command,
  };

  static OwnedProcess _fromJson(Map<String, dynamic> json) => OwnedProcess(
    role: json['role'] as String,
    pid: json['pid'] as int,
    groupId: json['groupId'] as int? ?? 0,
    startTime: json['startTime'] as String,
    command: json['command'] as String,
  );

  /// Le meneur : même PID, même heure de démarrage, et la commande vue finit
  /// par celle lancée (un `exec` en chaîne, ex. `uvx` → `uv tool uvx`, garde
  /// la fin).
  bool isSameAs(RunningProcess running) =>
      running.pid == pid &&
      running.startTime == startTime &&
      running.command.endsWith(command);

  /// Le meneur, ou un membre cohérent de son groupe : même groupe (jamais
  /// celui de l'app ni ≤ 1), démarré au plus tôt avec le meneur, même
  /// programme et mêmes arguments (éventuellement derrière un interpréteur,
  /// ex. `python …/voxmlx-serve --port 8100`). Un groupe ne peut être
  /// réutilisé qu'une fois vide : un membre cohérent prouve qu'il est à nous.
  bool owns(RunningProcess running, {required int appGroupId}) {
    if (isSameAs(running)) return true;
    if (!isSignallableGroup(groupId, appGroupId: appGroupId)) return false;
    if (running.groupId != groupId) return false;
    final DateTime? started = _parseLstart(running.startTime);
    final DateTime? recorded = _parseLstart(startTime);
    if (started == null || recorded == null || started.isBefore(recorded)) {
      return false;
    }
    return _sameProgram(running.command, command);
  }
}

/// Un groupe que l'app peut signaler : connu, ni ≤ 1, ni le sien.
bool isSignallableGroup(int groupId, {required int appGroupId}) =>
    groupId > 1 && groupId != appGroupId;

/// Restes notés qui tournent encore (meneur ou membre cohérent de son
/// groupe) : les seuls que l'app a le droit d'arrêter au lancement.
List<OwnedProcess> leftoversToKill(
  List<OwnedProcess> recorded,
  List<RunningProcess> running, {
  int appGroupId = 0,
}) => <OwnedProcess>[
  for (final OwnedProcess p in recorded)
    if (running.any((RunningProcess r) => p.owns(r, appGroupId: appGroupId))) p,
];

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Sun Nov 22 10:00:00 2026` (ps -o lstart=, LC_ALL=C) ; null si illisible.
DateTime? _parseLstart(String value) {
  final List<String> t = value.trim().split(RegExp(r'\s+'));
  if (t.length != 5) return null;
  final int month = _months.indexOf(t[1]) + 1;
  final List<int?> hms = t[3].split(':').map(int.tryParse).toList();
  final int? day = int.tryParse(t[2]);
  final int? year = int.tryParse(t[4]);
  if (month == 0 || hms.length != 3 || hms.contains(null)) return null;
  if (day == null || year == null) return null;
  return DateTime(year, month, day, hms[0]!, hms[1]!, hms[2]!);
}

String _base(String token) => token.split('/').last;

/// [seen] lance le même programme que [launched] avec les mêmes arguments,
/// directement ou derrière un interpréteur (premier mot ignoré).
bool _sameProgram(String seen, String launched) {
  final List<String> c = seen.trim().split(RegExp(r'\s+'));
  final List<String> r = launched.split(' ');
  for (int i = 0; i <= 1 && i < c.length; i++) {
    final List<String> tail = c.sublist(i);
    if (tail.length < 2 || tail.length > r.length) continue;
    final List<String> expected = r.sublist(r.length - tail.length);
    if (_base(tail.first) != _base(expected.first)) continue;
    bool same = true;
    for (int k = 1; k < tail.length && same; k++) {
      same = tail[k] == expected[k];
    }
    if (same) return true;
  }
  return false;
}

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

  /// Envoie [signal] au seul processus [pid].
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]);

  /// Envoie [signal] à tout le groupe [groupId].
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]);

  /// Groupe de processus de l'app elle-même (jamais signalé).
  int get appGroupId;

  /// Vrai si rien n'écoute sur 127.0.0.1:[port].
  Future<bool> isPortFree(int port);

  /// Vrai si [url] répond 200.
  Future<bool> isHealthy(Uri url);
}

/// Fichier d'état des serveurs lancés, dans le dossier de données de l'app
/// (un build de dev et la release ont chacun le leur).
String ownedProcessesFile() => '${appDataDirectory()}/servers.json';

final class _Live {
  _Live(this.process, this.port, this.record);

  final Process process;
  final int port;
  final OwnedProcess? record;
  bool exited = false;
}

/// Serveurs lancés par l'app : note PID, groupe et identité de chacun, les
/// arrête en vidant leur groupe (SIGTERM, puis SIGKILL après [grace]) et
/// nettoie au lancement les restes d'un arrêt brutal. Ne touche jamais un
/// processus ni un groupe qu'elle n'a pas lancé.
final class OwnedProcessRegistry {
  /// Cree un [OwnedProcessRegistry].
  OwnedProcessRegistry({required ProcessHost host, required String stateFile})
    : _host = host,
      _stateFile = File(stateFile);

  /// Délai entre SIGTERM et SIGKILL.
  static const Duration grace = Duration(seconds: 5);

  static const Duration _poll = Duration(milliseconds: 100);

  final ProcessHost _host;
  final File _stateFile;
  final Log _log = Log.named('OwnedProcessRegistry');
  final Map<String, _Live> _live = <String, _Live>{};

  /// Lance [executable] pour [role] sur [port] et le note. Arrête d'abord un
  /// serveur de [role] encore à nous. Lève [PortInUseException] si un autre
  /// programme tient [port] : rien n'est alors tué, lancé ni noté.
  Future<Process> start(
    String role,
    String executable,
    List<String> arguments, {
    required int port,
    Map<String, String>? environment,
  }) async {
    if (_live.containsKey(role)) await stop(role);
    if (!await _host.isPortFree(port)) throw PortInUseException(port);
    final Process process = await _host.start(
      executable,
      arguments,
      environment: environment,
    );
    final OwnedProcess? record = await _record(
      role,
      process.pid,
      <String>[executable.split('/').last, ...arguments].join(' '),
    );
    final _Live live = _Live(process, port, record);
    _live[role] = live;
    unawaited(process.exitCode.then((_) => _onLeaderExit(role, live)));
    return process;
  }

  /// Arrête le serveur de [role] lancé par ce registre ; sinon ne fait rien.
  /// Vide son groupe, puis attend (borné) que son port se libère.
  Future<void> stop(String role) async {
    final _Live? live = _live.remove(role);
    if (live == null) return;
    final OwnedProcess? record = live.record;
    final int pid = live.process.pid;
    final bool group = _signallable(record);
    if (group) {
      _host.killGroup(record!.groupId);
    } else if (!live.exited) {
      _host.kill(pid);
    }
    if (!await _waitUntil(() async => !await _liveAlive(live))) {
      _log.warning('$role encore vivant après SIGTERM, SIGKILL (pid $pid)');
      if (!live.exited) _host.kill(pid, ProcessSignal.sigkill);
      if (group && await _groupPopulated(record!)) {
        _host.killGroup(record.groupId, ProcessSignal.sigkill);
      }
      await _waitUntil(() async => !await _liveAlive(live));
    }
    _forget(role);
    for (int i = 0; i < 20 && !await _host.isPortFree(live.port); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Sonde de santé, par l'hôte.
  Future<bool> isHealthy(Uri url) => _host.isHealthy(url);

  /// Au lancement : arrête les restes notés (meneur de même identité, ou
  /// membre cohérent de leur groupe). Ne lève jamais.
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
    final int app = _host.appGroupId;
    for (final OwnedProcess p in leftoversToKill(
      recorded,
      running,
      appGroupId: app,
    )) {
      _log.info('Reste du lancement précédent: ${p.role} (pid ${p.pid})');
      await _terminateLeftover(p);
    }
    _write(<OwnedProcess>[
      for (final OwnedProcess p in _readOrEmpty())
        if (_live[p.role]?.process.pid == p.pid) p,
    ]);
  }

  // ---------------------------------------------------------------------------

  bool _signallable(OwnedProcess? p) =>
      p != null && isSignallableGroup(p.groupId, appGroupId: _host.appGroupId);

  /// Le meneur vit encore, ou son groupe a encore un membre.
  Future<bool> _liveAlive(_Live live) async {
    if (!live.exited) return true;
    final OwnedProcess? record = live.record;
    return _signallable(record) && await _groupPopulated(record!);
  }

  Future<bool> _groupPopulated(OwnedProcess p) async {
    try {
      return (await _host.running()).any(
        (RunningProcess r) => r.groupId == p.groupId,
      );
    } on Object {
      return false;
    }
  }

  /// Vrai si [done] devient vrai avant [grace].
  Future<bool> _waitUntil(Future<bool> Function() done) async {
    // Compté en sondes (pas d'horloge réelle) : borné à [grace].
    for (int i = 0; i * _poll.inMilliseconds < grace.inMilliseconds; i++) {
      if (await done()) return true;
      await Future<void>.delayed(_poll);
    }
    return done();
  }

  Future<void> _onLeaderExit(String role, _Live live) async {
    live.exited = true;
    if (!identical(_live[role], live)) return;
    // Meneur parti seul : l'entrée reste tant que son groupe a un membre
    // (stop ou le lancement suivant le videra).
    if (await _liveAlive(live)) return;
    if (!identical(_live[role], live)) return;
    _live.remove(role);
    _forget(role);
  }

  Future<void> _terminateLeftover(OwnedProcess p) async {
    final bool group = _signallable(p);
    Future<List<RunningProcess>?> ours() async {
      try {
        final int app = _host.appGroupId;
        return <RunningProcess>[
          for (final RunningProcess r in await _host.running())
            if (p.owns(r, appGroupId: app)) r,
        ];
      } on Object {
        return null;
      }
    }

    if (group) {
      _host.killGroup(p.groupId);
    } else {
      _host.kill(p.pid);
    }
    bool unreadable = false;
    final bool gone = await _waitUntil(() async {
      final List<RunningProcess>? left = await ours();
      unreadable = left == null;
      return left == null || left.isEmpty;
    });
    if (gone || unreadable) return;
    final List<RunningProcess> left = await ours() ?? <RunningProcess>[];
    if (left.any(p.isSameAs)) _host.kill(p.pid, ProcessSignal.sigkill);
    if (group && left.isNotEmpty) {
      _host.killGroup(p.groupId, ProcessSignal.sigkill);
    }
  }

  Future<OwnedProcess?> _record(String role, int pid, String command) async {
    final List<RunningProcess> running;
    try {
      running = await _host.running();
    } on Object catch (e) {
      _log.warning('Identité de $role (pid $pid) illisible, non notée: $e');
      return null;
    }
    final RunningProcess? seen = running
        .where((RunningProcess r) => r.pid == pid)
        .firstOrNull;
    if (seen == null) return null; // Déjà terminé : rien à nettoyer.
    final OwnedProcess record = OwnedProcess(
      role: role,
      pid: pid,
      groupId: seen.groupId,
      startTime: seen.startTime,
      command: command,
    );
    _write(<OwnedProcess>[
      for (final OwnedProcess p in _readOrEmpty())
        if (p.role != role) p,
      record,
    ]);
    return record;
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
