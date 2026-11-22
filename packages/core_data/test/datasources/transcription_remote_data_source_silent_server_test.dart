import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/fake_websocket_client.dart';

/// Tour 3, point 4 : serveur muet. La socket reste ouverte mais un commit
/// final ne reçoit jamais son `done`. Passé un délai borné (~20 s), la
/// source est traitée comme coupée : socket recyclée, audio sans `done`
/// renvoyé. Toujours sans réponse après les reprises : une seule perte le
/// couvre. Jamais de perte silencieuse.
void main() {
  const int t0 = 1700000000000;

  late FakeAsync clock;
  late FakeWebSocketClient mic;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<AudioGap> gaps;
  late List<domain.ConnectionState> states;

  void setUpIn(FakeAsync async) {
    clock = async;
    mic = FakeWebSocketClient(now: () => async.elapsed);
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: FakeWebSocketClient(),
    );
    gaps = <AudioGap>[];
    states = <domain.ConnectionState>[];
    dataSource.audioGaps.listen(gaps.add);
    dataSource.connectionState.listen(states.add);
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

  /// Phrase de 1 s puis pause : commit final envoyé (ids 0 à 21 envoyés).
  void utteranceThenPause() {
    feed(0, 10);
    feed(10, 15, voiced: false);
    expect(messageTypes(mic.received), contains('input_audio_buffer.commit'));
  }

  List<int> range(int from, int toExclusive) =>
      List<int>.generate(toExclusive - from, (int i) => from + i);

  test('un serveur lent qui répond en 8 s garde sa socket', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      utteranceThenPause();
      async.elapse(const Duration(seconds: 8));
      mic.emit(<String, Object>{
        'type': 'response.audio_transcript.done',
        'text': 'Bonjour.',
      });
      async.elapse(const Duration(minutes: 1));

      expect(mic.connectCalls, 1);
      expect(gaps, isEmpty);
    });
  });

  test('sans done après le délai, la socket est recyclée et la phrase '
      'renvoyée', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      utteranceThenPause();
      final int before = states.length;

      async.elapse(const Duration(seconds: 10));
      expect(mic.connectCalls, 1, reason: 'pas avant le délai');

      async.elapse(const Duration(seconds: 20));
      expect(mic.connectCalls, greaterThanOrEqualTo(2));
      expect(mic.connections.last.take(22), range(0, 22));
      expect(
        messageTypes(mic.connectionMessages.last),
        contains('input_audio_buffer.commit'),
      );
      expect(
        states.skip(before),
        anyOf(
          contains(domain.ConnectionState.connecting),
          contains(domain.ConnectionState.disconnected),
        ),
      );
    });
  });

  test('toujours muet après les reprises : une seule perte couvre la '
      'phrase, et elle n est plus renvoyée', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      utteranceThenPause();
      async.elapse(const Duration(minutes: 15));

      final List<AudioGap> micGaps = gaps
          .where((AudioGap g) => g.source == AudioSource.input)
          .toList();
      expect(micGaps, hasLength(1));
      expect(micGaps.single.startMs, lessThanOrEqualTo(t0));
      expect(micGaps.single.endMs, greaterThanOrEqualTo(t0 + 2200));
      expect(micGaps.single.endMs, lessThanOrEqualTo(t0 + 3000));

      int resends() =>
          mic.connections.where((List<int> c) => c.contains(0)).length;
      final int resentSoFar = resends();
      final int connectsSoFar = mic.connectCalls;
      async.elapse(const Duration(minutes: 15));
      expect(resends(), resentSoFar, reason: 'abandon après la perte');
      expect(connectsSoFar, lessThanOrEqualTo(20), reason: 'pas de boucle');
    });
  });
}
