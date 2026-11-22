import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #16, point 5 : un arrêt brutal pendant une coupure ou pendant
// l'attente du rattrapage ne doit pas perdre en silence l'audio en tampon.
// Dès qu'une source met de l'audio en attente (coupure, ou arrêt qui
// attend le rattrapage), un repère provisoire est écrit en base pour cette
// source ; il disparaît quand l'audio est livré. Après un arrêt brutal, le
// lancement suivant trouve le repère : la session est prête pour le
// rattrapage depuis le WAV (GapBackfillService.plan le voit).
//
// Dépôts en mémoire (InMemoryTranscriptRepository, contrat du port).
// Le repère provisoire suit la fin de l'audio en attente avec au plus 2 s
// de retard.
void main() {
  late FakeAsync clock;
  late FakeVoxServer server;
  late FakeVoxSocket mic;
  late LiveServiceHarness h;

  void setUpIn(FakeAsync async, {double? speed}) {
    clock = async;
    server = FakeVoxServer(now: () => async.elapsed, speed: speed);
    mic = FakeVoxSocket(server);
    h = LiveServiceHarness(
      async,
      remote: TranscriptionRemoteDataSourceImpl(
        micClient: mic,
        systemClient: FakeVoxSocket(server),
      ),
    )..start(outputEnabled: false);
  }

  void speak(int fromId, int count, {bool continuous = false}) {
    for (int id = fromId; id < fromId + count; id++) {
      final bool v = continuous || id % 100 < 80;
      h.audio.emit(
        chunk(AudioSource.input, id, timestampMs: h.t0 + id * 100, voiced: v),
      );
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  List<TranscriptSegmentEntity> markers() => h.segments
      .of(AudioSource.input)
      .where(
        (TranscriptSegmentEntity s) =>
            s.text.startsWith('Transcription interrompue'),
      )
      .toList();

  test('une coupure écrit tout de suite un repère provisoire, que le '
      'lancement suivant retrouve pour le rattrapage', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      speak(0, 50, continuous: true); // 5 s livrées
      mic
        ..refusing = true
        ..drop();
      speak(50, 100, continuous: true); // 10 s en attente

      expect(markers(), hasLength(1), reason: 'repère provisoire en base');
      expect(markers().single.timestampMs, lessThanOrEqualTo(5000));

      // « Arrêt brutal » : plus rien ne tourne ; au lancement suivant, la
      // base seule dit quoi rattraper.
      final plan = GapBackfillService.plan(
        h.segments.store.values
            .where((TranscriptSegmentEntity s) => s.sessionId == h.session.id)
            .toList(),
      );
      final int margin = GapBackfillService.margin.inMilliseconds;
      expect(plan, hasLength(1));
      expect(plan.single.source, AudioSource.input);
      expect(plan.single.startMs + margin, lessThanOrEqualTo(5000));
      expect(
        plan.single.endMs - margin,
        greaterThanOrEqualTo(13000),
        reason: 'couvre l audio en attente, à 2 s près',
      );
    });
  });

  test('l audio livré après la coupure, le repère provisoire disparaît', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      speak(0, 50, continuous: true);
      mic
        ..refusing = true
        ..drop();
      speak(50, 50, continuous: true);
      expect(markers(), hasLength(1));

      mic.refusing = false;
      speak(100, 200);
      async.elapse(const Duration(seconds: 20));

      expect(markers(), isEmpty);
    });
  });

  test('pendant l attente du rattrapage à l arrêt, un repère provisoire '
      'est en base, et disparaît quand tout est livré', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async, speed: 2);
      mic
        ..refusing = true
        ..drop();
      speak(0, 600); // arriéré de 60 s
      mic.refusing = false;
      speak(600, 20);

      bool stopped = false;
      unawaited(h.service.stopTranscription().then((_) => stopped = true));
      async.elapse(const Duration(seconds: 2));
      expect(stopped, isFalse, reason: 'l arrêt attend le rattrapage');
      expect(markers(), hasLength(1), reason: 'repère provisoire en base');

      for (int i = 0; i < 1500 && !stopped; i++) {
        async.elapse(const Duration(milliseconds: 100));
      }
      expect(stopped, isTrue);
      expect(markers(), isEmpty, reason: 'tout livré : plus de repère');
    });
  });
}
