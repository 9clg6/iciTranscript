import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 9, point 2 (sonde 7, scénario Dlag sans rattrapage, son système) :
// trois pertes déclarées au même instant (348,56 s), dans cet ordre :
// 1:58–2:04, 2:12–2:14, puis 1:51–2:35 qui contient les deux autres. Trois
// repères se chevauchaient dans la note.
//
// Attendu : les repères d'une source ne se chevauchent jamais. Une perte
// dans un repère encore ouvert, ou qui le touche, l'étend : un seul repère,
// l'union des intervalles ; le rattrapage planifie cette union une fois.
void main() {
  List<TranscriptSegmentEntity> markers(LiveServiceHarness h, AudioSource s) =>
      h.segments
          .of(s)
          .where(
            (TranscriptSegmentEntity x) =>
                x.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )
          .toList();

  void gap(LiveServiceHarness h, int startMs, int endMs) =>
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: h.t0 + startMs,
          endMs: h.t0 + endMs,
        ),
      );

  test('séquence enregistrée : un seul repère 00:01:51 – 00:02:35, planifié '
      'une fois', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(seconds: 348));
      gap(h, 118530, 124000); // 00:01:58 – 00:02:04
      gap(h, 132830, 134000); // 00:02:12 – 00:02:14
      gap(h, 111630, 155000); // 00:01:51 – 00:02:35
      async.elapse(const Duration(seconds: 1));

      final TranscriptSegmentEntity marker = markers(
        h,
        AudioSource.output,
      ).single;
      expect(marker.timestampMs, 111630);
      expect(marker.text, matches(RegExp(r'00:01:51\s*[–-]\s*00:02:35')));

      final plan = GapBackfillService.plan(h.segments.store.values.toList());
      expect(plan.where((p) => p.source == AudioSource.output), hasLength(1));

      // Revue PR #25, point 4 : l'écran aussi ne liste qu'un repère.
      final List<TranscriptSegmentEntity> listed = h
          .transcription
          .segmentsStream
          .value
          .where(
            (TranscriptSegmentEntity x) =>
                x.source == AudioSource.output &&
                x.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )
          .toList();
      expect(listed, hasLength(1), reason: 'un seul repère à l écran');
      expect(listed.single.text, marker.text);
    });
  });

  test('une perte qui touche un repère ouvert l étend ; une perte à part '
      'garde son propre repère', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(seconds: 200));
      gap(h, 60000, 70000);
      gap(h, 70000, 80000); // touche la fin du premier
      gap(h, 150000, 160000); // à part
      async.elapse(const Duration(seconds: 1));

      final List<TranscriptSegmentEntity> found = markers(h, AudioSource.output)
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      expect(found, hasLength(2));
      expect(found[0].text, matches(RegExp(r'00:01:00\s*[–-]\s*00:01:20')));
      expect(found[1].text, matches(RegExp(r'00:02:30\s*[–-]\s*00:02:40')));
    });
  });

  test('les repères de deux sources différentes ne fusionnent pas', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(seconds: 200));
      gap(h, 60000, 70000);
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.input,
          startMs: h.t0 + 65000,
          endMs: h.t0 + 75000,
        ),
      );
      async.elapse(const Duration(seconds: 1));

      expect(markers(h, AudioSource.output), hasLength(1));
      expect(markers(h, AudioSource.input), hasLength(1));
    });
  });
}
