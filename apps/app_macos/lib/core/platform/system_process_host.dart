import 'dart:io';

import 'package:ici_transcript/core/platform/owned_processes.dart';

final int _appPid = pid;

int? _groupOf(int pid) {
  final ProcessResult result = Process.runSync('/bin/ps', <String>[
    '-o',
    'pgid=',
    '-p',
    '$pid',
  ]);
  return int.tryParse((result.stdout as String).trim());
}

final int _appGroup = _groupOf(_appPid) ?? _appPid;

/// Chaque serveur part dans son propre groupe de processus (perl `setpgrp`
/// puis `exec`, même PID) : arrêter le groupe arrête aussi les enfants
/// (`uv` → `python`), même meneur parti, sans jamais toucher au groupe de
/// l'app.
const String _perl = '/usr/bin/perl';
const String _ownGroupThenExec =
    r'setpgrp(0, 0); exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!\n"';

// lstart : « Sun Nov 22 10:00:00 2026 », jour éventuellement complété d'un
// espace ; gardé tel quel (comparé à une valeur lue de la même façon).
final RegExp _psLine = RegExp(
  r'^\s*(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+[\d:]+\s+\d{4})\s+(.*)$',
);

/// Le vrai système. Seul fichier qui lance ou signale un processus.
final class SystemProcessHost implements ProcessHost {
  /// Cree un [SystemProcessHost].
  const SystemProcessHost();

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    // Les modes détachés passent déjà par setsid().
    // ponytail: sans /usr/bin/perl, pas de groupe propre (PID seul signalé).
    if (mode == ProcessStartMode.normal && File(_perl).existsSync()) {
      return Process.start(_perl, <String>[
        '-e',
        _ownGroupThenExec,
        '--',
        executable,
        ...arguments,
      ], environment: environment);
    }
    return Process.start(
      executable,
      arguments,
      environment: environment,
      mode: mode,
    );
  }

  @override
  Future<List<RunningProcess>> running() async {
    final ProcessResult result = await Process.run(
      '/bin/ps',
      <String>['-axww', '-o', 'pid=,pgid=,lstart=,command='],
      environment: <String, String>{'LC_ALL': 'C'},
    );
    if (result.exitCode != 0) {
      throw ProcessException('/bin/ps', const <String>[], '${result.stderr}');
    }
    return <RunningProcess>[
      for (final String line in (result.stdout as String).split('\n'))
        if (_psLine.firstMatch(line) case final RegExpMatch m)
          RunningProcess(
            pid: int.parse(m[1]!),
            groupId: int.parse(m[2]!),
            startTime: m[3]!,
            command: m[4]!,
          ),
    ];
  }

  @override
  int get appGroupId => _appGroup;

  /// Le seul PID ; jamais l'app ni init.
  @override
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (pid <= 1 || pid == _appPid) return false;
    return _send(signal, '$pid');
  }

  /// Tout le groupe ; jamais un groupe ≤ 1 ni celui de l'app (le registre
  /// ne passe que des groupes qu'il a notés).
  @override
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (groupId <= 1 || groupId == _appGroup) return false;
    return _send(signal, '-$groupId');
  }

  bool _send(ProcessSignal signal, String target) =>
      Process.runSync('/bin/kill', <String>[
        '-s',
        signal.toString().replaceFirst('SIG', ''),
        '--',
        target,
      ]).exitCode ==
      0;

  /// Une connexion à 127.0.0.1 qui aboutit = quelqu'un écoute (un bind
  /// d'essai peut réussir à côté d'une écoute sur 0.0.0.0).
  @override
  Future<bool> isPortFree(int port) async {
    try {
      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return false;
    } on SocketException catch (e) {
      // Délai dépassé sur la boucle locale : considéré comme pris.
      return e.osError != null;
    }
  }

  @override
  Future<bool> isHealthy(Uri url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 1);
    try {
      final HttpClientRequest request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 1));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
