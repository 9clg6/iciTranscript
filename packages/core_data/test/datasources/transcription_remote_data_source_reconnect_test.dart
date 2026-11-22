import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/fake_websocket_client.dart';

/// Réunions longues : une socket qui tombe ne doit perdre aucun audio.
///
/// Besoin T1.1 : pendant une coupure, l'audio reste accepté et mis en tampon
/// dans l'ordre (au moins 120 s par source), le client se reconnecte avec un
/// délai croissant, puis le tampon part dans l'ordre avant l'audio en direct.
/// Aucun chunk n'est envoyé deux fois. Au-delà de la borne, le plus ancien
/// est jeté et la perte est signalée avec sa durée, jamais en silence.
void main() {
  // Horodatage de capture (ms epoch, comme le plugin Swift).
  const int t0 = 1700000000000;

  late FakeAsync clock;
  late FakeWebSocketClient mic;
  late FakeWebSocketClient system;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<AudioGap> gaps;
  late List<domain.ConnectionState> states;

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
    dataSource.audioGaps.listen(gaps.add);
    dataSource.connectionState.listen(states.add);
    unawaited(dataSource.connect());
    async.flushMicrotasks();
  }

  /// Envoie [count] chunks consécutifs à partir de [fromId], un toutes les
  /// 100 ms de temps simulé.
  void feed(AudioSource source, int fromId, int count, {bool voiced = true}) {
    for (int id = fromId; id < fromId + count; id++) {
      dataSource.sendAudio(
        chunk(source, id, timestampMs: t0 + id * 100, voiced: voiced),
      );
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  List<int> range(int from, int toExclusive) =>
      List<int>.generate(toExclusive - from, (int i) => from + i);

  // Tour 2 (T1, point 2) : l'audio d'une phrase sans `done` est renvoyé sur
  // la nouvelle connexion. « Aucun chunk envoyé deux fois » vaut donc par
  // connexion : la socket morte ne l'a jamais transcrit.
  test('pendant une coupure, la phrase en cours puis l audio gardé repartent '
      'dans l ordre sur la nouvelle connexion, avant l audio en direct', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      feed(AudioSource.input, 0, 10);

      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 10, 50); // 5 s de coupure
      expect(mic.appendedChunkIds, range(0, 10));

      mic.accepting = true;
      feed(
        AudioSource.input,
        60,
        150,
      ); // la reconnexion arrive pendant ce temps

      expect(mic.connectCalls, greaterThan(1));
      expect(mic.connections.first, range(0, 10));
      expect(mic.connections.last, range(0, 210));
    });
  });

  test('un commit final émis pendant la coupure repart à sa place', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 0, 20); // phrase
      feed(AudioSource.input, 20, 20, voiced: false); // pause > 1,2 s
      feed(AudioSource.input, 40, 10); // phrase suivante
      expect(mic.received, isEmpty);

      mic.accepting = true;
      async.elapse(const Duration(seconds: 15));

      final List<String> types = messageTypes(mic.received);
      final int commit = types.indexOf('input_audio_buffer.commit');
      expect(commit, greaterThan(0), reason: 'le commit doit être renvoyé');
      final int appendsBeforeCommit = types
          .take(commit)
          .where((String type) => type == 'input_audio_buffer.append')
          .length;
      // Les 20 chunks voisés et la queue de silence précèdent le commit ;
      // la phrase suivante (ids 40+) le suit.
      expect(
        mic.appendedChunkIds
            .take(appendsBeforeCommit)
            .every((int id) => id < 40),
        isTrue,
      );
      expect(mic.appendedChunkIds.skip(appendsBeforeCommit).first, 40);
    });
  });

  test(
    'réessaie avec un délai croissant tant que le serveur refuse, sans boucle '
    'serrée ni abandon',
    () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        final int initialCalls = mic.connectCalls;
        final Duration dropAt = async.elapsed;
        mic.drop();
        mic.accepting = false;
        feed(AudioSource.input, 0, 600); // 60 s de refus

        final List<Duration> attempts = mic.connectAttempts
            .skip(initialCalls)
            .toList();
        expect(attempts, isNotEmpty);
        expect(
          attempts.first - dropAt,
          lessThanOrEqualTo(const Duration(seconds: 2)),
          reason: 'première tentative rapide',
        );
        expect(attempts.length, inInclusiveRange(3, 30));
        final List<Duration> intervals = <Duration>[
          for (int i = 1; i < attempts.length; i++)
            attempts[i] - attempts[i - 1],
        ];
        expect(intervals.last, greaterThan(intervals.first));
        expect(
          intervals.every((Duration d) => d <= const Duration(seconds: 10)),
          isTrue,
          reason:
              'délai plafonné : la reprise arrive vite une fois le '
              'serveur revenu',
        );
      });
    },
  );

  test('garde au moins 120 s d audio, jette le plus ancien au-delà et signale '
      'la perte avec sa durée', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 0, 1500); // 150 s de parole pendant la coupure

      // Reconnexion sans audio nouveau : le tampon n'évince plus rien.
      mic.accepting = true;
      async.elapse(const Duration(seconds: 15));
      feed(AudioSource.input, 1500, 150);

      final List<int> delivered = mic.appendedChunkIds;
      expect(delivered.last, 1649);
      final int firstKept = delivered.first;
      expect(
        delivered,
        range(firstKept, 1650),
        reason: 'le tampon garde une suite continue, la plus récente',
      );
      expect(
        1500 - firstKept,
        greaterThanOrEqualTo(1200),
        reason: 'au moins 120 s gardées',
      );

      final List<AudioGap> micGaps = gaps
          .where((AudioGap g) => g.source == AudioSource.input)
          .toList();
      expect(micGaps, hasLength(1), reason: 'une coupure, une perte');
      expect(micGaps.single.startMs, t0);
      expect(
        micGaps.single.duration.inMilliseconds,
        closeTo(firstKept * 100, 100),
      );
      expect(
        micGaps.single.endMs,
        lessThanOrEqualTo(t0 + firstKept * 100),
        reason: 'la perte ne couvre aucun chunk envoyé',
      );
    });
  });

  test('une coupure qui tient dans le tampon ne signale aucune perte', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 0, 600); // 60 s
      mic.accepting = true;
      feed(AudioSource.input, 600, 150);

      expect(gaps, isEmpty);
      expect(mic.appendedChunkIds, range(0, 750));
    });
  });

  test('le tampon se vide une fois renvoyé', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 0, 50);
      expect(
        dataSource.bufferedAudio(AudioSource.input),
        greaterThanOrEqualTo(const Duration(seconds: 4)),
      );

      mic.accepting = true;
      feed(AudioSource.input, 50, 150);

      expect(dataSource.bufferedAudio(AudioSource.input), Duration.zero);
      expect(dataSource.bufferedAudio(AudioSource.output), Duration.zero);
    });
  });

  test('l état de connexion montre la coupure puis le retour', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      expect(states.last, domain.ConnectionState.connected);
      final int before = states.length;

      mic.drop();
      mic.accepting = false;
      feed(AudioSource.input, 0, 20);
      expect(
        states.skip(before),
        anyOf(
          contains(domain.ConnectionState.disconnected),
          contains(domain.ConnectionState.connecting),
        ),
      );
      expect(states.last, isNot(domain.ConnectionState.connected));

      mic.accepting = true;
      feed(AudioSource.input, 20, 150);
      expect(states.last, domain.ConnectionState.connected);
    });
  });

  test('une source coupée n interrompt pas l autre', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.drop();
      mic.accepting = false;
      for (int id = 0; id < 50; id++) {
        dataSource.sendAudio(
          chunk(AudioSource.input, id, timestampMs: t0 + id * 100),
        );
        dataSource.sendAudio(
          chunk(AudioSource.output, id, timestampMs: t0 + id * 100),
        );
        async.elapse(const Duration(milliseconds: 100));
      }

      expect(system.appendedChunkIds, range(0, 50));
    });
  });

  test('après reconnexion, chaque done reçoit la fenêtre de sa phrase : la '
      'phrase renvoyée d abord, la suivante ensuite', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      final List<TranscriptEventRemoteModel> done =
          <TranscriptEventRemoteModel>[];
      dataSource.transcriptionStream
          .where(
            (TranscriptEventRemoteModel e) =>
                e.type == 'response.audio_transcript.done',
          )
          .listen(done.add);

      // Phrase A finalisée sur la connexion qui va tomber, sans `done`.
      feed(AudioSource.input, 0, 10);
      feed(AudioSource.input, 10, 15, voiced: false);
      mic.drop();
      async.elapse(const Duration(seconds: 15));

      // Phrase B : la coupure est vue, A est renvoyée, puis B.
      feed(AudioSource.input, 100, 10);
      feed(AudioSource.input, 110, 15, voiced: false);
      async.elapse(const Duration(seconds: 10));
      for (final String text in <String>['phrase A', 'phrase B']) {
        mic.emit(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': text,
        });
      }
      async.flushMicrotasks();

      expect(done, hasLength(2));
      expect(dataSource.windowOf(done[0])?.startMs, t0);
      expect(dataSource.windowOf(done[1])?.startMs, t0 + 100 * 100);
      expect(dataSource.activeSources, isEmpty);
    });
  });
}
