import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';
import '../helpers/fake_websocket_client.dart';

/// Tour 10, point 4 — borne de la poignée de main après un accueil rapide
/// (sonde 8, scénario B « slow2 », svc_slow2.jsonl).
///
/// Lecture par coupure (toutes sur le MICRO ; le son système n'est jamais
/// coupé) : délai d'accueil du proxy, tentatives, borne de la première :
/// - 40 s, 12 s : 40,59 puis 50,60 → première borne 10 s ;
/// - 100 s, 15 s : une tentative, acceptée à 15 s → borne apprise 20 s ;
/// - 160 s, 25 s : 160,58 puis 180,59 → première borne 20 s ; apprend 40 s ;
/// - 240 s, 1 s : une tentative ; le proxy relâche à 241,62 MAIS le premier
///   delta micro n'arrive qu'à 262,03 (après les autres coupures : 0,4 à
///   4 s) : côté client, l'accueil a pris ~20 s, pas 1 s ;
/// - 280 s, 12 s : une tentative, acceptée à 292,59 → première borne > 12 s ;
/// - nouvelle séance, 30 s, 12 s : 370,30 puis 380,31 → 10 s.
///
/// Le code retient la borne si la poignée de main a dépassé 10 s côté
/// client : l'accueil « de 1 s » à 240 s était lent pour lui ; la borne de
/// 40 s gardée explique la tentative unique à 280 s. C'est le banc (délai
/// du proxy pris pour la durée de l'accueil) qui diffère du réel, pas le
/// code. Rejoué avec les délais vus par le client : borne 10 s à 280 s si
/// l'accueil de 240 s a vraiment pris 1 s, 40 s s'il en a pris 21.
void main() {
  /// Coupe [socket] avec ce délai d'accueil et parle [seconds] s (les deux
  /// sources parlent ; le serveur répond en 0,4 s).
  void outage(
    DataSourceBench b,
    FakeWebSocketClient socket,
    Duration accept,
    int seconds,
    int Function() nextId,
  ) {
    socket
      ..acceptDelay = accept
      ..drop();
    for (int i = 0; i < seconds * 10; i++) {
      final int id = nextId();
      b.tick(
        id,
        voiced: <AudioSource, bool>{
          AudioSource.input: id % 100 < 75,
          AudioSource.output: id % 100 < 75,
        },
      );
    }
  }

  /// Écart entre les deux premières tentatives après [from] (null : une
  /// seule tentative a suffi).
  Duration? firstBound(FakeWebSocketClient socket, Duration from) {
    final List<Duration> after = socket.connectAttempts
        .where((Duration t) => t >= from)
        .toList();
    return after.length < 2 ? null : after[1] - after[0];
  }

  DataSourceBench bench(FakeAsync async) {
    final DataSourceBench b = DataSourceBench(async);
    b.mic.autoDoneAfter = const Duration(milliseconds: 400);
    b.system.autoDoneAfter = const Duration(milliseconds: 400);
    return b;
  }

  for (final (int fast, Duration? expected) in <(int, Duration?)>[
    (1, const Duration(seconds: 10)),
    (21, null),
  ]) {
    test(
      'calendrier B, accueil de ${fast}s à la 4e coupure : la 5e (12 s) '
      '${expected == null ? 'passe du premier coup (borne 40 s gardée)' : 'repart à 10 s'}',
      () {
        fakeAsync((FakeAsync async) {
          final DataSourceBench b = bench(async);
          int id = 0;
          int next() => id++;
          for (int i = 0; i < 400; i++) {
            b.tick(next());
          }
          outage(b, b.mic, const Duration(seconds: 12), 60, next);
          outage(b, b.mic, const Duration(seconds: 15), 60, next);
          outage(b, b.mic, const Duration(seconds: 25), 80, next);
          outage(b, b.mic, Duration(seconds: fast), 40, next);
          final Duration fifth = async.elapsed;
          outage(b, b.mic, const Duration(seconds: 12), 40, next);

          final Duration? bound = firstBound(b.mic, fifth);
          if (expected == null) {
            expect(bound, isNull, reason: 'une seule tentative');
          } else {
            expect(bound, isNotNull, reason: 'la première a expiré');
            expect(bound!, greaterThanOrEqualTo(expected));
            expect(
              bound,
              lessThan(expected + const Duration(milliseconds: 1500)),
            );
          }
        });
      },
    );
  }

  test('après un accueil rapide sur le micro, sa coupure suivante repart à '
      '10 s, même si le son système a appris 40 s', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = bench(async);
      int id = 0;
      int next() => id++;
      for (int i = 0; i < 400; i++) {
        b.tick(next());
      }
      outage(b, b.system, const Duration(seconds: 25), 80, next); // 40 s
      outage(b, b.mic, const Duration(seconds: 15), 60, next); // 20 s
      outage(b, b.mic, const Duration(seconds: 1), 40, next); // rapide
      final Duration drop = async.elapsed;
      outage(b, b.mic, const Duration(seconds: 12), 40, next);

      final Duration? bound = firstBound(b.mic, drop);
      expect(bound, isNotNull, reason: 'la première a expiré');
      expect(bound!, greaterThanOrEqualTo(const Duration(seconds: 10)));
      expect(bound, lessThan(const Duration(milliseconds: 11500)));
    });
  });

  test('un accueil rapide sur le son système ne remet pas la borne du micro '
      'à 10 s', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = bench(async);
      int id = 0;
      int next() => id++;
      for (int i = 0; i < 400; i++) {
        b.tick(next());
      }
      outage(b, b.mic, const Duration(seconds: 15), 60, next); // 20 s
      outage(b, b.system, const Duration(seconds: 1), 40, next); // rapide
      final Duration drop = async.elapsed;
      outage(b, b.mic, const Duration(seconds: 15), 60, next);

      expect(
        firstBound(b.mic, drop),
        isNull,
        reason: 'borne du micro gardée à 20 s : une tentative',
      );
    });
  });
}
