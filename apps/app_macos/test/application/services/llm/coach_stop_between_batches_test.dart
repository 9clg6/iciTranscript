import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';

import '../../../helpers/llm_fakes.dart' show ScriptedLlmProvider, requestText;

/// Arrêt de la passe du coach entre deux lots (revue de la PR #26).
///
/// Besoin : avec le modèle local, une longue note fait de nombreuses
/// générations après Arrêter ; une génération locale retarde la
/// transcription (1,8 s → 6–24 s mesurés). Quand un nouvel enregistrement
/// démarre, la passe s'arrête entre deux lots : le lot en cours finit et
/// compte, le reste est noté non analysé (« Réessayer » le reprendra),
/// sans erreur.
///
/// API supposée : `coachMeeting(..., shouldStop: bool Function())`, lu
/// avant chaque lot. Côté view model : post_call_coach_batches_test.dart.
void main() {
  TranscriptSegmentEntity seg(
    String id,
    String text, {
    required int atMs,
    AudioSource source = AudioSource.input,
  }) => TranscriptSegmentEntity(
    id: id,
    sessionId: 's1',
    source: source,
    text: text,
    timestampMs: atMs,
    createdAt: DateTime(2026, 11, 20, 9),
  );

  String answer(List<Map<String, String>> corrections) =>
      jsonEncode(<String, Object?>{'corrections': corrections});

  Map<String, String> fix(String original, String corrected) =>
      <String, String>{
        'original': original,
        'corrected': corrected,
        'category': 'grammar',
        'explanation': 'Explication courte.',
      };

  ScriptedLlmProvider replying(String text) => ScriptedLlmProvider(
    (LlmChatRequest r, int i) => Stream<String>.value(text),
  );

  List<TranscriptSegmentEntity> hourLong() => <TranscriptSegmentEntity>[
    for (int i = 0; i < 720; i++)
      seg(
        'me-$i',
        'Line $i: we need to check the figures for the next release.',
        atMs: i * 5000,
      ),
  ];

  String firstLineOf(LlmChatRequest r) =>
      RegExp(r'Line (\d+): we need').firstMatch(requestText(r))!.group(0)!;

  group('arrêt entre deux lots (un enregistrement démarre)', () {
    test('`shouldStop` vrai après le 1er lot : plus aucune requête, les '
        'corrections du 1er lot restent, le reste est non analysé', () async {
      bool stop = false;
      final ScriptedLlmProvider llm = ScriptedLlmProvider((
        LlmChatRequest r,
        int i,
      ) {
        stop = true;
        final String line = firstLineOf(r);
        return Stream<String>.value(
          answer(<Map<String, String>>[fix(line, '$line (corrigé)')]),
        );
      });
      final List<TranscriptSegmentEntity> meeting = hourLong();

      final EnglishFeedbackEntity feedback = await coachMeeting(
        llm,
        meeting,
        shouldStop: () => stop,
      );

      expect(llm.requests, hasLength(1));
      expect(feedback.corrections, hasLength(1));
      final String first = requestText(llm.requests.single);
      final Set<String> rest = <String>{
        for (final TranscriptSegmentEntity s in meeting)
          if (s.source == AudioSource.input && !first.contains(s.text)) s.id,
      };
      expect(rest, isNotEmpty);
      expect(feedback.unanalyzedSegmentIds.toSet(), rest);
    });

    test('`shouldStop` vrai dès le départ : aucune requête, tout est non '
        'analysé, pas d\'erreur', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));

      final EnglishFeedbackEntity feedback =
          await coachMeeting(llm, <TranscriptSegmentEntity>[
            seg('a', 'I am agree with you on this point.', atMs: 0),
            seg('b', 'He have sent the deck to the client.', atMs: 5000),
          ], shouldStop: () => true);

      expect(llm.requests, isEmpty);
      expect(feedback.unanalyzedSegmentIds.toSet(), <String>{'a', 'b'});
    });
  });
}
