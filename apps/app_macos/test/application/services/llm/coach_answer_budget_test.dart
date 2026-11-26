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

  final List<String> all = textsOf(denseMicMeeting(200));

  /// Réponse complète du factice à un lot des premières phrases de [all]
  /// tenant en [chars] caractères.
  String answerFor(int chars, {double ratio = kMeasuredAnswerCharsPerChar}) {
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
      answerCharsPerChar: ratio,
    );
  }

  test('prémisse du fournisseur factice, au ratio mesuré (~5) : ~1 450 '
      'caractères donnent ~7 300 caractères de réponse ; le lot du coach '
      'tient ; 3 500 et 9 300 caractères sont coupés', () {
    expect(answerFor(1450).length, inInclusiveRange(6500, 8200));
    expect(
      answerFor(kCoachBatchChars).length,
      lessThan(kProviderAnswerCutChars),
    );
    expect(
      answerFor(3500).length,
      greaterThan(kProviderAnswerCutChars),
      reason: 'des lots au-delà de ~3 200 caractères feraient couper',
    );
    expect(answerFor(9300).length, greaterThan(kProviderAnswerCutChars));
  });

  test('prémisse du locuteur plus dense (~12) : un lot de 1 500 caractères '
      'rend une réponse coupée, illisible ; sa moitié et une phrase seule '
      'se lisent', () {
    String cut(String full) => full.length <= kProviderAnswerCutChars
        ? full
        : full.substring(0, kProviderAnswerCutChars);
    const double dense = kDenserSpeakerAnswerCharsPerChar;

    expect(
      () => parseFeedback(cut(answerFor(1500, ratio: dense))),
      throwsA(isA<LlmMalformedAnswerException>()),
    );
    expect(
      parseFeedback(cut(answerFor(750, ratio: dense))).corrections,
      isNotEmpty,
    );
    expect(
      parseFeedback(cut(answerFor(110, ratio: dense))).corrections,
      hasLength(1),
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

    test('longue réunion au ratio mesuré : aucune réponse coupée, donc '
        'chaque phrase de l\'utilisateur part dans exactement une requête, '
        'et dans exactement un lot', () async {
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

  /// Besoin : un lot dont la réponse est illisible (coupée, mal formée) et
  /// qui a plus d'une phrase est coupé en deux, chaque moitié renvoyée (et
  /// ainsi de suite) : chaque phrase finit analysée. Une phrase seule qui
  /// échoue encore reste non analysée ; le nombre de requêtes est borné
  /// (≤ 2 × phrases : arbre binaire complet au pire).
  group('lot à la réponse illisible : coupé en deux et renvoyé', () {
    test('locuteur plus dense, ~12,5 k caractères : chaque phrase analysée, '
        'aucune erreur, requêtes ≤ 2 × phrases', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(125);
      final ScriptedLlmProvider llm = tokenLimitedCoach(
        textsOf(meeting),
        answerCharsPerChar: kDenserSpeakerAnswerCharsPerChar,
      );

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
      );
      expect(llm.requests.length, lessThanOrEqualTo(2 * meeting.length));
      expect(
        llm.requests.length,
        lessThanOrEqualTo(3 * coachBatches(meeting).length),
        reason:
            'chaque moitié tient : un lot illisible coûte au plus 3 '
            'requêtes (lui, puis ses deux moitiés), pas une par phrase',
      );
    });

    test('une phrase que le modèle ne sait jamais traiter : elle seule reste '
        'non analysée, les autres de son lot sont corrigées, sans erreur, '
        'requêtes ≤ 2 × phrases', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(30);
      final TranscriptSegmentEntity poison = meeting[7];
      final ScriptedLlmProvider llm = tokenLimitedCoach(
        textsOf(meeting),
        unreadableWith: poison.text,
      );

      final EnglishFeedbackEntity feedback = await coachMeeting(llm, meeting);

      expect(feedback.unanalyzedSegmentIds, <String>[poison.id]);
      expect(
        feedback.corrections
            .map((EnglishCorrectionEntity c) => c.original)
            .toSet(),
        <String>{
          for (final TranscriptSegmentEntity s in meeting)
            if (s.id != poison.id) coachOriginalOf(s.text),
        },
      );
      expect(llm.requests.length, lessThanOrEqualTo(2 * meeting.length));
    });

    test('modèle toujours illisible : la passe se termine, requêtes ≤ 2 × '
        'phrases, l\'erreur « illisible » remonte (tout a échoué)', () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(30);
      final ScriptedLlmProvider llm = ScriptedLlmProvider(
        (LlmChatRequest r, int i) => Stream<String>.value('{"overall": "Niv'),
      );

      await expectLater(
        coachMeeting(llm, meeting),
        throwsA(isA<LlmMalformedAnswerException>()),
      );
      expect(llm.requests.length, lessThanOrEqualTo(2 * meeting.length));
    });

    for (final (String name, LlmException error) in <(String, LlmException)>[
      ('injoignable', const LlmUnreachableException('mistral')),
      ('limite de débit', const LlmRateLimitedException('mistral')),
    ]) {
      test('fournisseur $name (pas une réponse illisible) : le lot n\'est pas '
          'coupé ni renvoyé', () async {
        final List<TranscriptSegmentEntity> meeting = denseMicMeeting(30);
        final ScriptedLlmProvider llm = ScriptedLlmProvider(
          (LlmChatRequest r, int i) => Stream<String>.error(error),
        );

        await expectLater(coachMeeting(llm, meeting), throwsA(same(error)));
        expect(llm.requests, hasLength(coachBatches(meeting).length));
      });
    }
  });
}
