import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #21 : les doublons de la sonde 6 ne venaient PAS de `done`
// tardifs (aucun `raw_done` pour eux dans svc_D.jsonl) mais de phrases
// partielles scellées ou repliées, rangées à l'heure d'arrivée de leur
// premier delta (voir sealed_partial_time_test.dart). Les specs qui
// écartaient un `done` sans fenêtre après une perte sont retirées.
//
// Garde : un `done` spontané sans fenêtre, avant ou longtemps après une
// perte, sur la même connexion ou une nouvelle, est toujours gardé comme
// une ligne. Un texte arrivé après l'arrêt n'est jamais rangé.
void main() {
  const String spontaneous = 'On passe au point suivant, le budget.';

  List<String> spoken(LiveServiceHarness h) => h.segments
      .of(AudioSource.input)
      .where(
        (TranscriptSegmentEntity s) =>
            !s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      )
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  void gap(LiveServiceHarness h) => h.fakeRemote.emitGap(
    AudioGap(
      source: AudioSource.input,
      startMs: h.t0 + 138000,
      endMs: h.t0 + 299000,
    ),
  );

  test('un done spontané sans fenêtre est gardé avant une perte, longtemps '
      'après, et après une reconnexion', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(AudioSource.input, 'Avant la perte.');
      async.elapse(const Duration(seconds: 1));

      async.elapse(const Duration(minutes: 5));
      gap(h);
      async.elapse(const Duration(seconds: 1));
      h.fakeRemote.emitDone(AudioSource.input, 'Juste après la perte.');
      async.elapse(const Duration(minutes: 3));
      h.fakeRemote.emitDone(AudioSource.input, spontaneous);
      async.elapse(const Duration(seconds: 1));

      h.fakeRemote
        ..emitConnectionState(domain.ConnectionState.disconnected)
        ..emitConnectionState(domain.ConnectionState.connected);
      async.elapse(const Duration(seconds: 5));
      h.fakeRemote.emitDone(AudioSource.input, 'Sur la nouvelle connexion.');
      async.elapse(const Duration(seconds: 1));

      expect(spoken(h), <String>[
        'Avant la perte.',
        'Juste après la perte.',
        spontaneous,
        'Sur la nouvelle connexion.',
      ]);
    });
  });

  test('un texte arrivé après l arrêt n est jamais rangé dans la session', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.stop();

      h.fakeRemote
        ..emitDelta(AudioSource.input, spontaneous)
        ..emitDone(AudioSource.input, spontaneous);
      async.elapse(const Duration(seconds: 5));

      expect(h.segments.store, isEmpty);
    });
  });
}
