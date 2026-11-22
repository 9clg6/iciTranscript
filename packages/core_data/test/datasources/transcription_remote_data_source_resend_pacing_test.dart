import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/fake_websocket_client.dart';

/// Tour 4, point 3 : après une reconnexion, l'arriéré n'est pas déversé
/// d'un bloc (sonde : 31 s renvoyées d'un bloc à côté d'un flux direct ont
/// fait monter un `done` à 38,8 s). Au plus ~30 s d'audio envoyé et pas
/// encore acquitté à la fois ; la phrase suivante part au `done` précédent.
/// L'audio direct attend dans l'ordre, sous la borne de 120 s.
void main() {
  const int t0 = 1700000000000;

  late FakeAsync clock;
  late FakeWebSocketClient mic;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<AudioGap> gaps;

  void setUpIn(FakeAsync async) {
    clock = async;
    mic = FakeWebSocketClient(now: () => async.elapsed)
      ..autoDoneAfter = const Duration(seconds: 3); // serveur lent mais vivant
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: FakeWebSocketClient(),
    );
    gaps = <AudioGap>[];
    dataSource.audioGaps.listen(gaps.add);
    dataSource.transcriptionStream.listen((_) {});
    unawaited(dataSource.connect(systemAudioEnabled: false));
    async.flushMicrotasks();
  }

  /// [count] cycles de parole : 8 s de voix, 2 s de pause (commit final).
  int speak(int fromId, int count) {
    int id = fromId;
    for (int n = 0; n < count; n++) {
      for (int k = 0; k < 100; k++, id++) {
        dataSource.sendAudio(
          chunk(
            AudioSource.input,
            id,
            timestampMs: t0 + id * 100,
            voiced: k < 80,
          ),
        );
        clock.elapse(const Duration(milliseconds: 100));
      }
    }
    return id;
  }

  test('l arriéré repart phrase par phrase, jamais plus de 30 s en vol', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic
        ..drop()
        ..accepting = false;
      int next = speak(0, 6); // 60 s de coupure : 6 phrases en attente
      mic.accepting = true;
      final int inFlightBefore = mic.maxInFlightChunks;
      next = speak(next, 6); // rattrapage pendant que la parole continue
      async.elapse(const Duration(seconds: 60));

      expect(inFlightBefore, lessThanOrEqualTo(100));
      expect(
        mic.maxInFlightChunks,
        lessThanOrEqualTo(300),
        reason: 'au plus 30 s envoyées sans done',
      );
      expect(gaps, isEmpty);
      final List<int> ids = mic.connections.last;
      for (int k = 1; k < ids.length; k++) {
        expect(ids[k], greaterThan(ids[k - 1]), reason: 'ordre');
      }
      expect(dataSource.bufferedAudio(AudioSource.input), Duration.zero);
      expect(dataSource.activeSources, isEmpty);
    });
  });
}
