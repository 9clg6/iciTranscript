import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Tour 5, point 4 (sonde 2 : reconnexion bloquée 30 s sur `channel.ready`).
/// Une poignée de main qui ne finit jamais est abandonnée après 10 s et
/// réessayée avec le délai croissant habituel ; la reprise ne perd rien.
void main() {
  test('une reconnexion sans réponse est abandonnée après 10 s puis '
      'réessayée', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic
        ..drop()
        ..hangConnect = true;
      for (int id = 0; id < 30; id++) {
        b.tick(id, voiced: const <AudioSource, bool>{AudioSource.input: true});
      }
      final int start = b.mic.connectAttempts.length;
      expect(start, greaterThanOrEqualTo(2), reason: 'une tentative pendue');
      final Duration hungAt = b.mic.connectAttempts.last;

      async.elapse(const Duration(seconds: 25));
      expect(b.mic.connectAttempts.length, greaterThan(start));
      final Duration retryAfter = b.mic.connectAttempts[start] - hungAt;
      expect(
        retryAfter,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
        reason: 'abandon à 10 s, pas avant',
      );
      expect(
        retryAfter,
        lessThanOrEqualTo(const Duration(seconds: 21)),
        reason: 'puis délai de reprise (≤ 10 s)',
      );

      b.mic.hangConnect = false;
      async.elapse(const Duration(seconds: 30));
      expect(b.mic.connections.last, List<int>.generate(30, (int i) => i));
      expect(b.gaps, isEmpty);
    });
  });

  test('la connexion de début de session qui ne répond pas échoue en '
      'temps borné', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.dataSource.disconnect();
      b.mic.hangConnect = true;
      Object? outcome;
      b.dataSource
          .connect(systemAudioEnabled: false)
          .then((_) => outcome = 'ok', onError: (Object e) => outcome = e);
      async.elapse(const Duration(seconds: 15));

      expect(outcome, isNotNull, reason: 'connect ne doit pas pendre');
      expect(outcome, isNot('ok'));
    });
  });
}
