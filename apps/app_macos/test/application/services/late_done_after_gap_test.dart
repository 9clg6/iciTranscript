import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 8, point a (sonde 6, machine très chargée, scénario D) : le serveur a
// rattrapé son retard pendant l'arrêt et a rendu, entre 306 et 410 s
// (réunion finie à 300 s), le texte de phrases dont l'audio était DANS une
// perte déjà déclarée (micro 00:02:18 – 00:04:59). Sans fenêtre, ce texte a
// été rangé à son heure d'ARRIVÉE (306,3 s, 317,5 s, 410,8 s), hors de la
// fenêtre de la perte ; le rattrapage a ensuite retrouvé les mêmes phrases
// → trois phrases en double.
//
// Règle choisie : ce texte est ÉCARTÉ (le rattrapage depuis le WAV possède
// l'intervalle). Preuve dans les journaux : les trois textes tardifs sont
// tronqués (« …malgré le vent froid, puis la », « …puis le libraire »,
// « …pendant la fête du village, ») alors que le rattrapage a rendu les
// trois phrases entières ; sans fenêtre, on ne sait pas non plus à quelle
// heure les placer. Un `done` spontané SANS perte déclarée reste une ligne
// (tour 4) ; un texte arrivé après l'arrêt n'est jamais rangé.
void main() {
  // Textes tardifs enregistrés (sonde 6, D).
  const List<String> lateMic = <String>[
    'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la',
    'La boulangère a repeint la serre pendant la fête du village,',
  ];
  const String lateSys =
      'La boulangère a décoré la cabane pendant la fête du village, puis le '
      'libraire';

  void declareRecordedGaps(LiveServiceHarness h) {
    h.fakeRemote
      ..emitGap(
        AudioGap(
          source: AudioSource.input,
          startMs: h.t0 + 138000,
          endMs: h.t0 + 299000,
        ),
      )
      ..emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: h.t0 + 129000,
          endMs: h.t0 + 299000,
        ),
      );
  }

  List<TranscriptSegmentEntity> spoken(LiveServiceHarness h, AudioSource s) => h
      .segments
      .of(s)
      .where(
        (TranscriptSegmentEntity x) =>
            !x.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      )
      .toList();

  test('après une perte déclarée, un done tardif sans fenêtre n est pas '
      'rangé à son heure d arrivée', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      declareRecordedGaps(h);
      async.elapse(const Duration(seconds: 1));

      for (final String text in lateMic) {
        h.fakeRemote.emitDone(AudioSource.input, text);
        async.elapse(const Duration(seconds: 5));
      }
      h.fakeRemote.emitDone(AudioSource.output, lateSys);
      async.elapse(const Duration(seconds: 5));

      expect(spoken(h, AudioSource.input), isEmpty);
      expect(spoken(h, AudioSource.output), isEmpty);
    });
  });

  test('ni par la phrase en cours scellée, ni par le repli de l arrêt', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      declareRecordedGaps(h);
      async.elapse(const Duration(seconds: 1));

      // Deltas tardifs, puis phrase perdue (scellée)…
      h.fakeRemote.emitDelta(AudioSource.input, lateMic[0]);
      async.elapse(const Duration(seconds: 5));
      h.fakeRemote.emitControl(AudioSource.input, utteranceLostEventType);
      async.elapse(const Duration(seconds: 1));
      // …et deltas tardifs encore en cours quand l'utilisateur arrête.
      h.fakeRemote.emitDelta(AudioSource.output, lateSys);
      async.elapse(const Duration(seconds: 5));
      h.stop();

      expect(spoken(h, AudioSource.input), isEmpty);
      expect(spoken(h, AudioSource.output), isEmpty);
    });
  });

  test('sans perte déclarée, un done spontané reste une ligne (tour 4)', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(AudioSource.input, 'On commence la réunion.');
      async.elapse(const Duration(seconds: 1));

      expect(
        spoken(h, AudioSource.input).map((TranscriptSegmentEntity s) => s.text),
        <String>['On commence la réunion.'],
      );
    });
  });

  test('un texte arrivé après l arrêt n est jamais rangé dans la session', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.stop();

      h.fakeRemote
        ..emitDelta(AudioSource.input, lateMic[1])
        ..emitDone(AudioSource.input, lateMic[1]);
      async.elapse(const Duration(seconds: 5));

      expect(h.segments.store, isEmpty);
    });
  });
}
