import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';

import '../../../helpers/coach_fakes.dart';
import '../../../helpers/llm_fakes.dart';

/// Coach anglais sur une longue réunion : la RÉPONSE du modèle est bornée
/// (4 096 jetons), pas seulement la requête.
///
/// Bug (2026-11-26, note de 78 min) : chaque lot échoue en « Réponse du
/// modèle illisible », 90/116 phrases non analysées. Cause prouvée sur le
/// vrai fournisseur : un lot de ~9,4 k caractères d'anglais parlé demande
/// plus de corrections que 4 096 jetons n'en contiennent ; la réponse est
/// coupée au milieu du JSON (`finish_reason: length`).
///
/// Besoin épinglé ici :
/// - une réunion de 9 à 13 k caractères au micro est analysée en entier
///   par un fournisseur qui coupe sa réponse comme le vrai
///   ([tokenLimitedCoach]) : une correction par phrase, aucune phrase non
///   analysée, aucune erreur ;
/// - chaque requête du coach demande un nombre borné de corrections, si
///   bien que la pire réponse permise tient dans [kLlmAnswerMaxTokens] ;
/// - garde-fous : une courte transcription reste une seule requête, chaque
///   phrase part dans exactement une requête.
///
/// Contrat de la borne (spec « au plus N corrections ») : le texte de
/// chaque requête du coach (consignes + message) contient « at most N
/// corrections » (casse indifférente, N en chiffres), avec
/// N ≥ 1 et N × 400 (pire correction) + 400 (pire `overall`) ≤
/// [kLlmAnswerMaxTokens] × [kAnswerCharsPerToken] (soit N ≤ 38 à 4 096
/// jetons).
void main() {
  /// Pire correction permise : passage fautif et correction d'une phrase,
  /// catégorie, explication COURTE en français, syntaxe JSON.
  const int worstCorrectionChars = 400;
  const int worstOverallChars = 400;
  final RegExp cap = RegExp(r'at most (\d+) corrections', caseSensitive: false);

  List<String> textsOf(List<TranscriptSegmentEntity> meeting) => <String>[
    for (final TranscriptSegmentEntity s in meeting) s.text,
  ];

  int micChars(List<TranscriptSegmentEntity> meeting) =>
      textsOf(meeting).join('\n').length;

  test('prémisse du fournisseur factice : un lot de la taille d\'aujourd\'hui '
      'est coupé, un lot de ~3 000 caractères tient avec de la marge', () {
    final List<String> all = textsOf(denseMicMeeting(200));
    String answerFor(int chars) {
      final List<String> batch = <String>[];
      for (final String s in all) {
        if (batch.join('\n').length + s.length + 1 > chars) break;
        batch.add(s);
      }
      return fullCoachAnswer(
        LlmChatRequest(
          systemPrompt: '',
          messages: <LlmMessage>[
            LlmMessage(role: LlmRole.user, content: batch.join('\n')),
          ],
          maxTokens: kLlmAnswerMaxTokens,
        ),
        all,
      );
    }

    expect(answerFor(9300).length, greaterThan(kProviderAnswerCutChars));
    expect(
      answerFor(3000).length,
      lessThan(kProviderAnswerCutChars ~/ 2),
      reason: '3 000 caractères doivent tenir deux fois',
    );
  });

  group('une longue réunion dense, fournisseur qui coupe à 4 096 jetons', () {
    test('~12,5 k caractères au micro : analysée en entier, une correction '
        'par phrase, aucune phrase non analysée, aucune erreur', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(125);
      expect(micChars(meeting), inInclusiveRange(9000, 13000));
      final ScriptedLlmProvider llm = tokenLimitedCoach(textsOf(meeting));

      final EnglishFeedbackEntity feedback = await coachMeeting(llm, meeting);

      expect(
        feedback.unanalyzedSegmentIds,
        isEmpty,
        reason:
            '${feedback.unanalyzedSegmentIds.length}/${meeting.length} '
            'phrases non analysées en ${llm.requests.length} requêtes',
      );
      expect(
        feedback.corrections
            .map((EnglishCorrectionEntity c) => c.original)
            .toSet(),
        <String>{for (final String s in textsOf(meeting)) coachOriginalOf(s)},
        reason: 'chaque phrase de chaque partie a sa correction',
      );
    });

    test('~9 k caractères (une seule requête aujourd\'hui) : pas de « réponse '
        'illisible », tout est analysé', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(90);
      expect(micChars(meeting), inInclusiveRange(9000, 13000));
      final ScriptedLlmProvider llm = tokenLimitedCoach(textsOf(meeting));

      final EnglishFeedbackEntity feedback = await coachMeeting(llm, meeting);

      expect(feedback.unanalyzedSegmentIds, isEmpty);
      expect(feedback.corrections, hasLength(meeting.length));
    });
  });

  group('chaque requête demande un nombre borné de corrections', () {
    void expectBounded(LlmChatRequest r) {
      final RegExpMatch? m = cap.firstMatch(requestText(r));
      expect(
        m,
        isNotNull,
        reason: 'la requête ne dit pas « at most N corrections »',
      );
      final int n = int.parse(m!.group(1)!);
      expect(n, greaterThanOrEqualTo(1));
      expect(
        n * worstCorrectionChars + worstOverallChars,
        lessThanOrEqualTo(kLlmAnswerMaxTokens * kAnswerCharsPerToken),
        reason: 'au plus $n corrections ne tient pas dans la réponse',
      );
    }

    test('après la réunion et sur la note : chaque requête envoyée dit « at '
        'most N corrections », N tenant dans la réponse', () async {
      for (final List<TranscriptSegmentEntity> meeting
          in <List<TranscriptSegmentEntity>>[
            denseMicMeeting(3),
            denseMicMeeting(125),
          ]) {
        final ScriptedLlmProvider llm = tokenLimitedCoach(textsOf(meeting));

        await coachMeeting(llm, meeting);

        expect(llm.requests, isNotEmpty);
        llm.requests.forEach(expectBounded);
      }
    });

    test('en direct (`coachRequest`, faible latence) : même borne', () {
      for (final List<CoachLine> batch in coachBatches(denseMicMeeting(125))) {
        expectBounded(coachRequest(batch, preferLowLatency: true));
        expectBounded(coachRequest(batch));
      }
    });
  });

  group('garde-fous', () {
    test('courte transcription (quelques centaines de caractères) : une '
        'seule requête', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(3);
      expect(micChars(meeting), lessThan(500));
      final ScriptedLlmProvider llm = tokenLimitedCoach(textsOf(meeting));

      final EnglishFeedbackEntity feedback = await coachMeeting(llm, meeting);

      expect(llm.requests, hasLength(1));
      expect(feedback.corrections, hasLength(3));
    });

    test('longue réunion : chaque phrase de l\'utilisateur part dans '
        'exactement une requête, et dans exactement un lot', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(125);
      final ScriptedLlmProvider llm = tokenLimitedCoach(textsOf(meeting));

      await coachMeeting(llm, meeting);

      for (final TranscriptSegmentEntity s in meeting) {
        final int carrying = llm.requests
            .where((LlmChatRequest r) => requestText(r).contains(s.text))
            .length;
        expect(carrying, 1, reason: '« ${s.text} » envoyée $carrying fois');
      }
      final List<String> batched = <String>[
        for (final List<CoachLine> b in coachBatches(meeting))
          for (final CoachLine l in b) l.id,
      ];
      expect(batched, <String>[
        for (final TranscriptSegmentEntity s in meeting) s.id,
      ]);
    });
  });
}
