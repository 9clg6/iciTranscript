import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/fake_websocket_client.dart';

/// Tour 2, point 2 : l'audio d'une phrase déjà parti sur une socket morte
/// n'a jamais été transcrit. Le client garde l'audio depuis le dernier
/// commit jusqu'à son `done`, et le renvoie sur la nouvelle connexion avant
/// l'audio plus récent. S'il ne tient pas dans la borne, il est compté dans
/// une seule perte, aux bonnes heures. Jamais de perte silencieuse.
void main() {
  const int t0 = 1700000000000;

  late FakeAsync clock;
  late FakeWebSocketClient mic;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<AudioGap> gaps;

  void setUpIn(FakeAsync async) {
    clock = async;
    mic = FakeWebSocketClient(now: () => async.elapsed);
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

  void feed(int fromId, int count, {bool voiced = true}) {
    for (int id = fromId; id < fromId + count; id++) {
      dataSource.sendAudio(
        chunk(
          AudioSource.input,
          id,
          timestampMs: t0 + id * 100,
          voiced: voiced,
        ),
      );
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  void done(String text) {
    mic.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': text,
    });
    clock.flushMicrotasks();
  }

  List<int> range(int from, int toExclusive) =>
      List<int>.generate(toExclusive - from, (int i) => from + i);

  test('une phrase commitée dont le done n est jamais venu repart avec son '
      'commit, avant l audio plus récent', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      feed(0, 10); // phrase A
      feed(10, 15, voiced: false); // pause : commit final de A (vivant)
      expect(messageTypes(mic.received), contains('input_audio_buffer.commit'));

      mic.drop();
      mic.accepting = false;
      feed(30, 10); // phrase B pendant la coupure
      mic.accepting = true;
      async.elapse(const Duration(seconds: 15));

      // A = 10 chunks voisés + 1,2 s de queue de silence (ids 0 à 21).
      final List<int> resent = mic.connections.last;
      expect(resent, <int>[...range(0, 22), ...range(30, 40)]);
      final List<String> types = messageTypes(mic.connectionMessages.last);
      expect(types.indexOf('input_audio_buffer.commit'), 22);
    });
  });

  test('une phrase dont le done est arrivé n est pas renvoyée', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      feed(0, 10);
      feed(10, 15, voiced: false); // commit de A
      done('phrase A');

      feed(30, 10); // phrase B, pas encore commitée
      mic.drop();
      mic.accepting = false;
      feed(40, 10);
      mic.accepting = true;
      async.elapse(const Duration(seconds: 15));

      expect(mic.connections.last, range(30, 50));
    });
  });

  // Tour 4 (renvoi étalé) : le serveur factice répond à chaque commit final
  // en 1 s ; l'arriéré gardé part phrase par phrase, jamais plus d'une
  // phrase de 30 s en vol sans done.
  test('au-delà de 120 s, la phrase non transcrite est la première perdue, '
      'dans une seule perte aux bonnes heures ; le reste part étalé', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.autoDoneAfter = const Duration(seconds: 1);
      feed(0, 50); // 5 s de phrase partis sur la socket qui va tomber
      mic.drop();
      mic.accepting = false;
      feed(50, 1500); // 150 s de parole pendant la coupure
      mic.accepting = true;
      async.elapse(const Duration(seconds: 60));

      final List<int> resent = mic.connections.last;
      final int firstKept = resent.first;
      expect(resent, range(firstKept, 1550));
      expect(1550 - firstKept, greaterThanOrEqualTo(1200));

      expect(gaps, hasLength(1));
      expect(gaps.single.source, AudioSource.input);
      expect(gaps.single.startMs, t0, reason: 'début de la phrase perdue');
      expect(gaps.single.endMs, t0 + firstKept * 100);
      expect(mic.maxInFlightChunks, lessThanOrEqualTo(320));
    });
  });

  // Tour 4 : avec le renvoi étalé et la vivacité (60 s sans aucun message,
  // commit en attente), un serveur qui ne répond jamais ne reçoit pas
  // l'arriéré d'un bloc : au plus ~30 s en vol par connexion, recyclages
  // bornés, puis l'audio jamais acquitté tombe dans des pertes signalées.
  test('sans done pendant 10 min, le renvoi reste borné et l audio jamais '
      'acquitté tombe dans des pertes signalées', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      Duration maxBuffered = Duration.zero;
      for (int id = 0; id < 6000; id += 100) {
        feed(id, 100); // 10 min de parole, jamais de done
        final Duration b = dataSource.bufferedAudio(AudioSource.input);
        if (b > maxBuffered) maxBuffered = b;
      }
      async.elapse(const Duration(minutes: 30)); // plus de parole
      expect(mic.connectCalls, inInclusiveRange(2, 40));
      expect(
        maxBuffered,
        lessThanOrEqualTo(const Duration(seconds: 125)),
        reason: 'tampon borné',
      );
      expect(dataSource.bufferedAudio(AudioSource.input), Duration.zero);
      bool inGap(int id) => gaps.any(
        (AudioGap g) => t0 + id * 100 >= g.startMs && t0 + id * 100 < g.endMs,
      );
      final List<int> unaccounted = <int>[
        for (int id = 0; id < 6000; id++)
          if (!inGap(id)) id,
      ];
      expect(
        unaccounted,
        isEmpty,
        reason:
            'audio jamais acquitté ni signalé '
            '(premier : ${unaccounted.isEmpty ? '-' : unaccounted.first})',
      );

      final int connects = mic.connectCalls;
      async.elapse(const Duration(minutes: 15));
      expect(mic.connectCalls, connects, reason: 'abandon, plus de boucle');

      expect(
        mic.maxInFlightChunks,
        lessThanOrEqualTo(320),
        reason: 'jamais l arriéré d un bloc',
      );
    });
  });
}
