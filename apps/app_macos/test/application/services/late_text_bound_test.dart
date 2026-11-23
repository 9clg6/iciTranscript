import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #21, bloquant : la règle « texte tardif d'une perte » est
// collante. Après UNE perte, tout texte sans fenêtre de la source est écarté
// jusqu'à la fin de la réunion, sans repère, alors que le rattrapage ne
// possède que l'intervalle perdu.
//
// Attendu (ce que l'utilisateur voit : segments rangés, et leur heure) :
// a. une fois arrivés les textes tardifs de la perte, un texte spontané
//    sans fenêtre, minutes plus tard, est GARDÉ comme une ligne ;
// b. la règle est bornée à ce que la perte a abandonné : si elle a laissé
//    N phrases attendues, au plus N textes tardifs sont écartés, le N+1e est
//    gardé ;
// d. après remplacement de la connexion, rien n'est écarté : les réponses
//    de l'ancienne connexion ne peuvent plus arriver (N = 0).
//
// API supposée : `AudioGap.abandonedUtterances` (int, 0 par défaut) : les
// phrases de la source envoyées sur la connexion TOUJOURS vivante dont le
// `done` n'était pas venu quand la perte a été déclarée (leur texte peut
// encore arriver). Textes tardifs : ceux enregistrés par la sonde 6 (D).
void main() {
  const List<String> lateTexts = <String>[
    'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, '
        'puis la',
    'La boulangère a repeint la serre pendant la fête du village,',
  ];
  const String later = 'On passe au point suivant, le budget du trimestre.';

  List<String> spoken(LiveServiceHarness h) => h.segments
      .of(AudioSource.input)
      .where(
        (TranscriptSegmentEntity s) =>
            !s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      )
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  void gap(LiveServiceHarness h, {required int abandoned}) =>
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.input,
          startMs: h.t0 + 138000,
          endMs: h.t0 + 299000,
          abandonedUtterances: abandoned,
        ),
      );

  test('a. les textes tardifs de la perte arrivés, un texte spontané '
      'minutes plus tard est gardé', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(minutes: 5));
      gap(h, abandoned: lateTexts.length);
      async.elapse(const Duration(seconds: 1));
      for (final String t in lateTexts) {
        h.fakeRemote.emitDone(AudioSource.input, t);
        async.elapse(const Duration(seconds: 3));
      }
      expect(spoken(h), isEmpty, reason: 'les textes tardifs sont écartés');

      async.elapse(const Duration(minutes: 3));
      h.fakeRemote.emitDone(AudioSource.input, later);
      async.elapse(const Duration(seconds: 1));

      expect(spoken(h), <String>[later]);
    });
  });

  test('b. au plus N textes écartés pour N phrases abandonnées ; le N+1e '
      'est gardé', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(minutes: 5));
      gap(h, abandoned: 1);
      async.elapse(const Duration(seconds: 1));

      h.fakeRemote.emitDone(AudioSource.input, lateTexts[0]);
      async.elapse(const Duration(seconds: 3));
      h.fakeRemote.emitDone(AudioSource.input, lateTexts[1]);
      async.elapse(const Duration(seconds: 3));

      expect(spoken(h), <String>[lateTexts[1]]);
    });
  });

  test('d. connexion remplacée (aucune phrase abandonnée sur une connexion '
      'vivante) : rien n est écarté', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(minutes: 5));
      gap(h, abandoned: 0);
      async.elapse(const Duration(seconds: 1));

      h.fakeRemote.emitDone(AudioSource.input, later);
      async.elapse(const Duration(seconds: 1));

      expect(spoken(h), <String>[later]);
    });
  });
}
