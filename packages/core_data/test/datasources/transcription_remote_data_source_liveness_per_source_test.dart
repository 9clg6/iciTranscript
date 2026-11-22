import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Tour 5, point 2 : vivacité PAR source. Sonde 2 : les messages système
/// masquaient un micro mort pendant plus de 117 s. Une source dont un
/// commit final attend et qui ne reçoit aucun message à elle pendant 60 s
/// est recyclée, même si l'autre source parle.
///
/// 60 s par source reste compatible avec un serveur lent mais vivant : la
/// sonde a mesuré au plus 38,8 s entre un commit et son `done`, et 28,9 s
/// entre deux `done` d'une même source pendant un rattrapage (marge ≥ 1,5).
/// Les gardes « done en 40 s » et « deltas de la même socket » restent dans
/// transcription_remote_data_source_silent_server_test.dart.
void main() {
  test('micro muet 60 s avec un commit en attente : recyclé et renvoyé '
      'malgré un système bavard', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      for (int id = 0; id < 25; id++) {
        b.tick(id, voiced: <AudioSource, bool>{AudioSource.input: id < 10});
      }
      for (int s = 0; s < 55; s += 2) {
        b.systemChatter();
        async.elapse(const Duration(seconds: 2));
      }
      expect(b.mic.connectCalls, 1, reason: 'pas avant 60 s');

      for (int s = 0; s < 20; s += 2) {
        b.systemChatter();
        async.elapse(const Duration(seconds: 2));
      }

      expect(b.mic.connectCalls, greaterThanOrEqualTo(2));
      expect(
        b.mic.connections.last.take(10),
        List<int>.generate(10, (int i) => i),
      );
      expect(b.system.connectCalls, 1, reason: 'le système vit');
    });
  });

  test('un done micro à 40 s, système bavard, ne recycle rien', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      for (int id = 0; id < 25; id++) {
        b.tick(id, voiced: <AudioSource, bool>{AudioSource.input: id < 10});
      }
      for (int s = 0; s < 40; s += 2) {
        b.systemChatter();
        async.elapse(const Duration(seconds: 2));
      }
      b.mic.emit(<String, Object>{
        'type': 'response.audio_transcript.done',
        'text': 'Bonjour.',
      });
      async.elapse(const Duration(minutes: 2));

      expect(b.mic.connectCalls, 1);
      expect(b.gaps, isEmpty);
    });
  });
}
