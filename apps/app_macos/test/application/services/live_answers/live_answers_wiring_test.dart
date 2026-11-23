import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

import '../../../helpers/live_answers_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Branchement (T4, besoins 1 et 10) : les questions partent des phrases
/// FINALES de la transcription en direct, jamais du texte provisoire qui
/// grandit (sinon une question partirait à chaque mot, ou à moitié dite).
///
/// API supposée :
/// - `LiveTranscriptionService.finalizedSegmentsStream` :
///   `Stream<TranscriptSegmentEntity>`, un événement par segment définitif
///   sauvé (deux sources) ; rien pour les morceaux provisoires, les points
///   de sauvegarde, ni les phrases écartées par les filtres.
/// - Le view model du direct relie ce flux à
///   `LiveAnswersService.onSegmentFinalized` (avec l'interlocuteur connu) ;
///   ici le test fait ce lien lui-même.
void main() {
  test('les morceaux provisoires ne sortent pas ; la phrase finale sort une '
      'fois, avec son texte et sa source', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
      live.service.finalizedSegmentsStream.listen(finals.add);

      live.fakeRemote.emitDelta(AudioSource.output, 'Est-ce que vous');
      async.elapse(const Duration(seconds: 5));
      live.fakeRemote.emitDelta(AudioSource.output, ' avez prévu une date');
      // Au-delà d'un point de sauvegarde de la phrase en cours.
      async.elapse(const Duration(seconds: 20));
      expect(finals, isEmpty);

      live.fakeRemote.emitDone(
        AudioSource.output,
        'Est-ce que vous avez prévu une date de livraison ?',
      );
      async.elapse(const Duration(seconds: 1));

      expect(finals, hasLength(1));
      expect(
        finals.single.text,
        'Est-ce que vous avez prévu une date de livraison ?',
      );
      expect(finals.single.source, AudioSource.output);
      expect(
        live.segments.store.containsKey(finals.single.id),
        isTrue,
        reason: 'l\'id est celui du segment sauvé',
      );
    });
  });

  test('une phrase écartée par les filtres ne sort pas', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
      live.service.finalizedSegmentsStream.listen(finals.add);

      live.fakeRemote.emitDone(AudioSource.output, 'Продолжение следует');
      async.elapse(const Duration(seconds: 1));

      expect(finals, isEmpty);
    });
  });

  test('les phrases du micro sortent aussi (contexte, « Répondre à cette '
      'phrase »)', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
      live.service.finalizedSegmentsStream.listen(finals.add);

      live.fakeRemote.emitDone(AudioSource.input, 'Bonjour à tous.');
      async.elapse(const Duration(seconds: 1));

      expect(finals.map((TranscriptSegmentEntity s) => s.source), <AudioSource>[
        AudioSource.input,
      ]);
    });
  });

  test('bout en bout : une question dite par un autre participant donne une '
      'seule question et une seule requête, même après des morceaux '
      'provisoires', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final LiveAnswersHarness answers = LiveAnswersHarness();
      live.service.finalizedSegmentsStream.listen(
        // Session `s1` du faux service de réponses.
        (TranscriptSegmentEntity s) =>
            answers.service.onSegmentFinalized(s.copyWith(sessionId: 's1')),
      );

      for (final String delta in <String>[
        'Quand',
        ' est-ce que',
        ' vous livrez',
      ]) {
        live.fakeRemote.emitDelta(AudioSource.output, delta);
        async.elapse(const Duration(seconds: 2));
      }
      expect(answers.llm.requests, isEmpty);

      live.fakeRemote.emitDone(
        AudioSource.output,
        'Quand est-ce que vous livrez le lot 1 ?',
      );
      async.elapse(const Duration(milliseconds: 500));

      expect(answers.questions, hasLength(1));
      expect(answers.questions.single.status, LiveQuestionStatus.answering);
      expect(answers.llm.requests, hasLength(1));
    });
  });
}
