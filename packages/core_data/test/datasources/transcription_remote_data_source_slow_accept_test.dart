import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Tour 8, point b (sonde 6, machine très chargée) : le serveur vivant
/// acceptait chaque reconnexion après plus de 10 s ; le client abandonnait
/// à 10 s → 5 tentatives de suite ratées, micro coupé 75 s.
///
/// Attendu : la borne de la poignée de main s'adapte — après une tentative
/// expirée, la suivante attend plus longtemps (10 s, 20 s, 40 s, puis 60 s
/// au plus) ; l'attente entre deux
/// tentatives ne s'ajoute pas à un accueil déjà lent. L'audio reste en
/// tampon dans les bornes habituelles, les pertes sont signalées comme
/// avant.
void main() {
  /// Coupe le micro et continue de parler [seconds] s (une phrase de 8 s,
  /// 2 s de pause, par cycle).
  List<int> dropAndSpeak(DataSourceBench b, int seconds) {
    b.mic.drop();
    return b.speak(AudioSource.input, 0, seconds ~/ 10);
  }

  test('un accueil en 12 s : la tentative suivante, plus patiente, '
      'aboutit (au plus 10 + 12 s)', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic.acceptDelay = const Duration(seconds: 12);
      async.elapse(const Duration(seconds: 1)); // connexion initiale faite
      final Duration droppedAt = async.elapsed;
      dropAndSpeak(b, 30);

      expect(b.mic.connections, hasLength(2), reason: 'reconnecté');
      final List<Duration> after = b.mic.connectAttempts
          .where((Duration t) => t >= droppedAt)
          .toList();
      expect(after.length, lessThanOrEqualTo(2));
      expect(
        after.last - droppedAt,
        lessThanOrEqualTo(const Duration(seconds: 11)),
        reason: 'pas d attente en plus de la borne de 10 s',
      );
    });
  });

  test('un accueil en 15 s : reconnecté, sans tempête, audio livré sans '
      'perte', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic
        ..acceptDelay = const Duration(seconds: 15)
        ..autoDoneAfter = const Duration(seconds: 1);
      async.elapse(const Duration(seconds: 1)); // connexion initiale faite
      final Duration droppedAt = async.elapsed;
      final List<int> voiced = dropAndSpeak(b, 60);

      final List<Duration> after = b.mic.connectAttempts
          .where((Duration t) => t >= droppedAt)
          .toList();
      expect(after.length, lessThanOrEqualTo(2), reason: 'pas de tempête');
      expect(b.mic.connections, hasLength(2));
      expect(b.gaps, isEmpty);
      expect(
        voiced.where((int id) => !b.mic.appendedChunkIds.contains(id)),
        isEmpty,
        reason: 'tout l audio de la coupure livré',
      );
    });
  });

  test('la borne grandit après chaque échec : 10, 20, 40, puis 60 s au '
      'plus, sans attente en plus', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic.acceptDelay = const Duration(minutes: 10); // jamais à temps
      async.elapse(const Duration(seconds: 1)); // connexion initiale faite
      final Duration droppedAt = async.elapsed;
      dropAndSpeak(b, 300);

      final List<Duration> attempts = b.mic.connectAttempts
          .where((Duration t) => t >= droppedAt)
          .toList();
      final List<Duration> intervals = <Duration>[
        for (int i = 1; i < attempts.length; i++) attempts[i] - attempts[i - 1],
      ];
      const List<int> bounds = <int>[10, 20, 40, 60, 60, 60];
      expect(intervals.length, greaterThanOrEqualTo(bounds.length));
      for (int i = 0; i < bounds.length; i++) {
        expect(
          intervals[i],
          greaterThanOrEqualTo(Duration(seconds: bounds[i])),
          reason: 'tentative ${i + 1} : attend sa borne',
        );
        expect(
          intervals[i],
          lessThanOrEqualTo(Duration(milliseconds: bounds[i] * 1000 + 1500)),
          reason: 'tentative ${i + 1} : rien de plus que sa borne',
        );
      }
    });
  });

  test('un serveur qui n accepte jamais à temps : tampon borné, perte '
      'signalée comme avant', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic.acceptDelay = const Duration(minutes: 10);
      dropAndSpeak(b, 200);

      expect(
        b.dataSource.bufferedAudio(AudioSource.input),
        lessThanOrEqualTo(const Duration(seconds: 125)),
      );
      b.dataSource.disconnect();
      async.flushMicrotasks();
      expect(
        b.gaps.where((AudioGap g) => g.source == AudioSource.input),
        isNotEmpty,
        reason: 'la perte est signalée (au plus tard à l arrêt)',
      );
    });
  });

  // Revue PR #21 (commit 1250d05) : une seule poignée de main à la fois.
  test('une tentative à la fois ; à expiration le canal est fermé et jamais '
      'réutilisé ; une nouvelle coupure repart à 10 s', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic.acceptDelay = const Duration(seconds: 15);
      async.elapse(const Duration(seconds: 1));
      final Duration firstDrop = async.elapsed;
      b.mic.drop();
      for (int id = 0; id < 90; id++) {
        b.tick(
          id,
          voiced: <AudioSource, bool>{AudioSource.input: id % 50 < 40},
        );
        final List<Duration> attempts = b.mic.connectAttempts
            .where((Duration t) => t >= firstDrop)
            .toList();
        final Duration since = async.elapsed - firstDrop;
        if (since < const Duration(seconds: 10)) {
          expect(
            attempts.length,
            lessThanOrEqualTo(1),
            reason: 'pas de 2e tentative pendant la borne ($since)',
          );
        }
        if (since < const Duration(seconds: 24)) {
          expect(
            b.mic.connections,
            hasLength(1),
            reason: 'la tentative expirée ne se connecte jamais ($since)',
          );
        }
      }
      async.elapse(const Duration(seconds: 30));
      expect(b.mic.connections, hasLength(2), reason: 'reconnecté');

      // Nouvelle coupure : la borne repart à 10 s.
      final Duration secondDrop = async.elapsed;
      b.mic.drop();
      for (int id = 1000; id < 1150; id++) {
        b.tick(
          id,
          voiced: <AudioSource, bool>{AudioSource.input: id % 50 < 40},
        );
      }
      final List<Duration> again = b.mic.connectAttempts
          .where((Duration t) => t >= secondDrop)
          .toList();
      expect(again.length, greaterThanOrEqualTo(2));
      expect(
        again[1] - again[0],
        lessThanOrEqualTo(const Duration(milliseconds: 11500)),
        reason: 'première borne de la nouvelle coupure : 10 s',
      );
      expect(
        again[1] - again[0],
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
    });
  });
}
