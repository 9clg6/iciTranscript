import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Tour 5, point 3 (côté source distante) : `disconnect()` ne jette jamais
/// d'audio sans perte signalée (sonde 2 : 90 s en D, 52,8 s en E perdues en
/// silence). Tout ce qui n'a pas son `done`, envoyé ou non, finit dans une
/// seule perte par source, aux bonnes heures.
void main() {
  const int t0 = DataSourceBench.t0;

  List<AudioGap> micGaps(DataSourceBench b) =>
      b.gaps.where((AudioGap g) => g.source == AudioSource.input).toList();

  test('arrêt pendant un rattrapage étalé, sans coupure en cours : une '
      'perte couvre l arriéré et l audio en vol', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic
        ..drop()
        ..accepting = false;
      b.speak(AudioSource.input, 0, 6); // 6 phrases, aucune acquittée
      b.mic.accepting = true;
      async.elapse(const Duration(seconds: 12)); // reconnecté, pas de done

      b.dataSource.disconnect();
      async.flushMicrotasks();

      final List<AudioGap> gaps = micGaps(b);
      expect(gaps, hasLength(1));
      expect(gaps.single.startMs, t0);
      // Dernier chunk envoyé : 8 s de voix + 1,2 s de queue du 6e cycle.
      expect(gaps.single.endMs, t0 + 59200);
    });
  });

  test('arrêt après une fermeture de socket passée inaperçue : une perte '
      'couvre la phrase', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      for (int id = 0; id < 50; id++) {
        b.tick(id, voiced: const <AudioSource, bool>{AudioSource.input: true});
      }
      b.mic.drop(notify: false);

      b.dataSource.disconnect();
      async.flushMicrotasks();

      final List<AudioGap> gaps = micGaps(b);
      expect(gaps, hasLength(1));
      expect(gaps.single.startMs, t0);
      expect(gaps.single.endMs, t0 + 5000);
    });
  });

  test('arrêt après des phrases toutes acquittées : aucune perte', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic.autoDoneAfter = const Duration(milliseconds: 500);
      b.speak(AudioSource.input, 0, 3);
      async.elapse(const Duration(seconds: 2));

      b.dataSource.disconnect();
      async.flushMicrotasks();

      expect(b.gaps, isEmpty);
    });
  });
}
