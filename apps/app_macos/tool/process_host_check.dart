// ignore_for_file: avoid_print
// Real check of the OS adapter (SystemProcessHost + OwnedProcessRegistry) on
// harmless processes only: /bin/sleep and a small /bin/sh chain, started by
// this script, on unused ports 47811-47814 (only probed, never listened on).
// State file in a temp directory, never the app data directory. Signals go
// only to processes this script started; no kill by name.
// Run: fvm flutter test --no-pub tool/process_host_check.dart
import 'dart:convert';
import 'dart:io';

import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/platform/system_process_host.dart';

const SystemProcessHost host = SystemProcessHost();
final List<RunningProcess> started = <RunningProcess>[];

Future<RunningProcess?> find(int pid) async => (await host.running())
    .where((RunningProcess r) => r.pid == pid)
    .firstOrNull;

Future<List<RunningProcess>> members(int group) async => <RunningProcess>[
  for (final RunningProcess r in await host.running())
    if (r.groupId == group) r,
];

Future<RunningProcess> track(int pid) async {
  final RunningProcess r = (await find(pid))!;
  started.add(r);
  return r;
}

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) throw StateError(what);
}

Future<void> main() async {
  final Directory dir = Directory.systemTemp.createTempSync('host_check_');
  final String state = '${dir.path}/servers.json';
  print('state file: $state, app group ${host.appGroupId}');
  try {
    // (a) sleep through the host: own group; stop empties it.
    final OwnedProcessRegistry reg = OwnedProcessRegistry(
      host: host,
      stateFile: state,
    );
    final Process a = await reg.start('a', '/bin/sleep', <String>[
      '300',
    ], port: 47811);
    final RunningProcess ra = await track(a.pid);
    print('(a) pid ${ra.pid} pgid ${ra.groupId} cmd "${ra.command}"');
    check(ra.groupId == ra.pid, '(a) PID == PGID');
    await reg.stop('a');
    check((await members(ra.groupId)).isEmpty, '(a) group empty after stop');

    // (b) leader exits on TERM, child ignores TERM: group SIGKILL after grace.
    final Process control = await host.start('/bin/sleep', <String>['300']);
    final RunningProcess rc = await track(control.pid);
    final Process b = await reg.start('b', '/bin/sh', <String>[
      '-c',
      'trap "exit 0" TERM; (trap "" TERM; exec sleep 300) & wait',
    ], port: 47812);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final RunningProcess rb = await track(b.pid);
    final List<RunningProcess> chain = await members(rb.groupId);
    for (final RunningProcess r in chain) {
      if (r.pid != rb.pid) started.add(r);
    }
    print('(b) group ${rb.groupId}: ${chain.map((r) => r.pid).toList()}');
    check(chain.length == 2, '(b) leader + child in one group');
    final Stopwatch w = Stopwatch()..start();
    await reg.stop('b');
    print('(b) stop took ${w.elapsedMilliseconds} ms');
    check((await members(rb.groupId)).isEmpty, '(b) child gone (group KILL)');
    check(await find(rc.pid) != null, '(b) control sleep untouched');

    // (c) crash: new registry on the same state file, launch cleanup.
    final Process c = await reg.start('c', '/bin/sleep', <String>[
      '300',
    ], port: 47813);
    final RunningProcess rcc = await track(c.pid);
    await OwnedProcessRegistry(
      host: host,
      stateFile: state,
    ).cleanUpLeftovers();
    check(await find(rcc.pid) == null, '(c) leftover stopped at launch');
    final String left = File(state).existsSync()
        ? File(state).readAsStringSync()
        : '[]';
    check(
      !(jsonDecode(left) as List<dynamic>).any(
        (dynamic e) => (e as Map<String, dynamic>)['role'] == 'c',
      ),
      '(c) entry removed',
    );

    // (d) live unrelated PID recorded with a wrong start time: untouched.
    File(state).writeAsStringSync(
      jsonEncode(<Object>[
        <String, Object>{
          'role': 'd',
          'pid': rc.pid,
          'groupId': rc.groupId,
          'startTime': 'Sat Jan  1 00:00:00 2000',
          'command': 'uvx voxmlx-serve --port 47814',
        },
      ]),
    );
    await OwnedProcessRegistry(
      host: host,
      stateFile: state,
    ).cleanUpLeftovers();
    final RunningProcess? still = await find(rc.pid);
    check(
      still != null && still.startTime == rc.startTime,
      '(d) unrelated process untouched',
    );
  } finally {
    // Only what this script started, matched by PID + start time.
    for (final RunningProcess r in started) {
      final RunningProcess? now = await find(r.pid);
      if (now != null && now.startTime == r.startTime) {
        host.kill(r.pid, ProcessSignal.sigkill);
        print('cleanup: killed own pid ${r.pid}');
      }
    }
    dir.deleteSync(recursive: true);
  }
}
