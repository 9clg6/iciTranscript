import 'dart:async';
import 'dart:math' as math;

import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';
import '../helpers/fake_websocket_client.dart';

/// Tour 5, point 5 : invariant sous pannes tirées au hasard (graine fixe).
/// Serveur séquentiel lent (une file pour les deux sockets, 2× le temps
/// réel, deltas pendant le traitement), coupures notifiées ou non, refus de
/// connexion, blocages du serveur, arrêt à un instant tiré.
///
/// Chaque chunk voisé donné à la source distante avant l'arrêt finit soit
/// transcrit (une seule fois, dans l'ordre), soit dans une perte signalée.
/// Pas de troisième issue.
void main() {
  for (int seed = 1; seed <= 12; seed++) {
    test('graine $seed : transcrit une fois dans l ordre, ou signalé', () {
      fakeAsync((FakeAsync async) => _run(async, seed));
    });
  }
}

void _run(FakeAsync async, int seed) {
  final math.Random rng = math.Random(seed);
  final DataSourceBench b = DataSourceBench(async);
  final _SequentialServer server = _SequentialServer(async)
    ..attach(b.mic)
    ..attach(b.system);

  const int sessionTicks = 10 * 60 * 10; // 10 min
  final int stopTick = 5 * 60 * 10 + rng.nextInt(5 * 60 * 10);
  // Pannes : une toutes les 20 à 80 s.
  final Map<int, void Function()> faults = <int, void Function()>{};
  for (
    int t = 200 + rng.nextInt(600);
    t < stopTick;
    t += 200 + rng.nextInt(600)
  ) {
    final FakeWebSocketClient socket = rng.nextBool() ? b.mic : b.system;
    final int kind = rng.nextInt(4);
    final int seconds = <int>[5, 20, 60, 150][rng.nextInt(4)];
    faults[t] = switch (kind) {
      0 => () => socket.drop(notify: rng.nextBool()), // coupure seule
      1 => () {
        socket
          ..accepting = false
          ..drop(notify: rng.nextBool());
        Timer(Duration(seconds: seconds), () => socket.accepting = true);
      },
      2 => () => server.stall(Duration(seconds: 10 + rng.nextInt(80))),
      _ => () => socket.drop(), // fermeture serveur vue par le canal
    };
  }

  final Map<AudioSource, List<int>> voiced = <AudioSource, List<int>>{
    AudioSource.input: <int>[],
    AudioSource.output: <int>[],
  };
  for (int i = 0; i < sessionTicks && i < stopTick; i++) {
    faults[i]?.call();
    final bool mv = i % 100 < 80;
    final bool sv = (i + 50) % 100 < 70;
    if (mv) voiced[AudioSource.input]!.add(i);
    if (sv) voiced[AudioSource.output]!.add(i);
    b.tick(
      i,
      voiced: <AudioSource, bool>{
        AudioSource.input: mv,
        AudioSource.output: sv,
      },
    );
  }
  b.dataSource.disconnect();
  async.elapse(const Duration(minutes: 5));

  for (final AudioSource source in AudioSource.values) {
    final FakeWebSocketClient socket = b.socketOf(source);
    expect(
      socket.transcribedTwice,
      isEmpty,
      reason: '${source.name} : doublon',
    );
    final List<int> order = socket.transcribedOrder;
    for (int k = 1; k < order.length; k++) {
      if (order[k] <= order[k - 1]) {
        fail('${source.name} : ${order[k]} transcrit après ${order[k - 1]}');
      }
    }
    final List<int> neither = <int>[];
    final List<int> both = <int>[];
    for (final int id in voiced[source]!) {
      final bool t = socket.transcribedIds.contains(id);
      final bool g = b.inGap(source, id);
      if (!t && !g) neither.add(id);
      if (t && g) both.add(id);
    }
    expect(
      neither,
      isEmpty,
      reason:
          '${source.name} : ${neither.length} chunks ni transcrits ni '
          'signalés (premier : ${neither.isEmpty ? '-' : neither.first})',
    );
    expect(both, isEmpty, reason: '${source.name} : transcrit ET signalé');
  }
}

/// File unique, 2× le temps réel ; blocages ; deltas pendant le travail.
final class _SequentialServer {
  _SequentialServer(this.async);

  final FakeAsync async;
  Duration _busyUntil = Duration.zero;
  Duration _stalledUntil = Duration.zero;

  void attach(FakeWebSocketClient socket) {
    socket.onFinalCommit = (List<int> ids, int generation) =>
        _enqueue(socket, ids, generation);
  }

  void stall(Duration d) {
    final Duration until = async.elapsed + d;
    if (until > _stalledUntil) _stalledUntil = until;
    if (until > _busyUntil) _busyUntil = until;
  }

  void _enqueue(FakeWebSocketClient socket, List<int> ids, int generation) {
    final Duration now = async.elapsed;
    Duration start = _busyUntil > now ? _busyUntil : now;
    if (_stalledUntil > start) start = _stalledUntil;
    _busyUntil = start + Duration(milliseconds: ids.length * 50);
    for (
      Duration t = start + const Duration(seconds: 2);
      t < _busyUntil;
      t += const Duration(seconds: 2)
    ) {
      Timer(t - now, () {
        socket.emitIfAlive(generation, <String, Object>{
          'type': 'response.audio_transcript.delta',
          'delta': '… ',
        });
      });
    }
    Timer(_busyUntil + const Duration(milliseconds: 400) - now, () {
      socket.emitIfAlive(generation, <String, Object>{
        'type': 'response.audio_transcript.done',
        'text': 'phrase',
      });
    });
  }
}
