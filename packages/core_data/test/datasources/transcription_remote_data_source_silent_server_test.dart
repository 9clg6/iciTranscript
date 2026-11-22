import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/fake_websocket_client.dart';

/// Vivacité du serveur (tour 4, d'après la sonde du serveur réel) :
/// - le serveur traite les sockets l'une après l'autre ; pendant un
///   rattrapage, un `done` a mis 38,8 s et deux `done` ont été séparés de
///   28,9 s, serveur vivant. La vivacité se juge donc sur TOUT message du
///   serveur, sur TOUTES ses sockets ;
/// - serveur vraiment muet : aucun message sur aucune socket pendant 60 s
///   alors qu'un commit final attend → coupure (recyclage, renvoi), puis une
///   seule perte. 60 s ≈ 2 × 28,9 s et au-delà de 38,8 s.
void main() {
  const int t0 = 1700000000000;

  late FakeAsync clock;
  late FakeWebSocketClient mic;
  late FakeWebSocketClient system;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<AudioGap> gaps;
  late List<domain.ConnectionState> states;
  late List<TranscriptEventRemoteModel> micDone;

  void setUpIn(FakeAsync async) {
    clock = async;
    mic = FakeWebSocketClient(now: () => async.elapsed);
    system = FakeWebSocketClient(now: () => async.elapsed);
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: system,
    );
    gaps = <AudioGap>[];
    states = <domain.ConnectionState>[];
    micDone = <TranscriptEventRemoteModel>[];
    dataSource.audioGaps.listen(gaps.add);
    dataSource.connectionState.listen(states.add);
    dataSource.transcriptionStream
        .where(
          (TranscriptEventRemoteModel e) =>
              e.type == 'response.audio_transcript.done',
        )
        .listen(micDone.add);
    dataSource.systemTranscriptionStream.listen((_) {});
    unawaited(dataSource.connect());
    async.flushMicrotasks();
  }

  void feed(AudioSource source, int fromId, int count, {bool voiced = true}) {
    for (int id = fromId; id < fromId + count; id++) {
      dataSource.sendAudio(
        chunk(source, id, timestampMs: t0 + id * 100, voiced: voiced),
      );
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  /// Phrase micro de 1 s puis pause : commit final envoyé (ids 0 à 21).
  void micUtteranceThenPause({int from = 0}) {
    feed(AudioSource.input, from, 10);
    feed(AudioSource.input, from + 10, 15, voiced: false);
  }

  void doneOn(FakeWebSocketClient socket, String text) {
    socket.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': text,
    });
    clock.flushMicrotasks();
  }

  List<int> range(int from, int toExclusive) =>
      List<int>.generate(toExclusive - from, (int i) => from + i);

  group('vivacité jugée sur tout message du serveur (point 1)', () {
    test('un done micro qui met 40 s pendant que l autre socket parle ne '
        'recycle rien', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        micUtteranceThenPause();
        for (int s = 0; s < 40; s += 2) {
          system.emit(<String, Object>{
            'type': 'response.audio_transcript.delta',
            'delta': 'suite ',
          });
          if (s % 10 == 8) doneOn(system, 'Phrase système.');
          async.elapse(const Duration(seconds: 2));
        }
        doneOn(mic, 'Bonjour.');
        async.elapse(const Duration(minutes: 1));

        expect(mic.connectCalls, 1);
        expect(system.connectCalls, 1);
        expect(gaps, isEmpty);
        expect(dataSource.windowOf(micDone.single)?.startMs, t0);
      });
    });

    test('des deltas sur la même socket pendant 50 s suffisent aussi', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        micUtteranceThenPause();
        for (int s = 0; s < 50; s += 5) {
          mic.emit(<String, Object>{
            'type': 'response.audio_transcript.delta',
            'delta': 'bon',
          });
          async.elapse(const Duration(seconds: 5));
        }
        doneOn(mic, 'Bonjour.');
        async.elapse(const Duration(minutes: 1));

        expect(mic.connectCalls, 1);
        expect(gaps, isEmpty);
      });
    });

    test('un serveur au repos, sans commit en attente, n est jamais '
        'recyclé', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        micUtteranceThenPause();
        doneOn(mic, 'Bonjour.');
        async.elapse(const Duration(minutes: 10));

        expect(mic.connectCalls, 1);
        expect(system.connectCalls, 1);
      });
    });
  });

  group('serveur vraiment muet (point 2)', () {
    test('rien pendant 55 s : pas encore recyclé ; avant 75 s, recyclé et '
        'phrase renvoyée', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        micUtteranceThenPause();
        final int before = states.length;

        async.elapse(const Duration(seconds: 55));
        expect(mic.connectCalls, 1, reason: 'pas avant le délai de 60 s');

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
        micUtteranceThenPause();
        async.elapse(const Duration(minutes: 30));

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
  });

  group('done spontané et done vide (point 4)', () {
    test('un done sans commit en attente ne prend la fenêtre d aucune '
        'phrase suivante', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        doneOn(mic, 'Fin de phrase vue par le modèle.');
        micUtteranceThenPause(from: 100);
        doneOn(mic, 'Phrase B.');

        expect(micDone, hasLength(2));
        expect(dataSource.windowOf(micDone[0]), isNull);
        expect(dataSource.windowOf(micDone[1])?.startMs, t0 + 100 * 100);
        expect(dataSource.activeSources, isEmpty);
      });
    });

    test('un done vide acquitte son commit : la phrase n est ni attendue ni '
        'renvoyée après une coupure', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        micUtteranceThenPause();
        doneOn(mic, '');
        expect(dataSource.activeSources, isEmpty);

        mic.drop();
        feed(AudioSource.input, 100, 10);
        async.elapse(const Duration(seconds: 15));

        expect(mic.connections.last, isNot(contains(0)));
        expect(mic.connections.last.first, 100);
      });
    });
  });
}
