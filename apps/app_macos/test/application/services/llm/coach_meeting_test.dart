import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_prompt.dart'
    show questionLanguage;
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';

import '../../../helpers/llm_fakes.dart' show ScriptedLlmProvider, requestText;

/// Coach anglais d'une note, règle unique (après l'appel ET à la demande).
///
/// Besoin (Clément) : corriger ce que l'UTILISATEUR a dit en anglais, jamais
/// les autres participants. Comportement épinglé ici :
/// - seules les phrases du micro partent ; jamais l'audio système, un repère
///   de perte (« Transcription interrompue… ») ni un « Passage non
///   transcrit » ; une phrase en français de l'utilisateur n'est pas envoyée ;
/// - règle de langue, qui ne s'en remet PAS au seul `questionLanguage` : une
///   phrase de l'utilisateur part seulement si elle a au moins un mot-outil
///   anglais (pronom, article, auxiliaire, préposition : « I », « so »,
///   « the »…) ET aucun mot-outil français (« le », « la », « fait »…) ;
///   sinon ignorée. Un mot des deux langues (« on », « a ») ne compte pas
///   comme français. Franglais (« On fait le call with the team. », que
///   `questionLanguage` juge anglais) : ignoré. « OK », « yes »,
///   « exactly » sont des interjections, pas des mots-outils ;
/// - un modèle qui dit en prose qu'il n'y a rien à corriger = aucune
///   correction pour cette partie, pas un échec ;
/// - une longue réunion part en plusieurs requêtes d'au plus
///   [kLlmMaxRequestChars] caractères (consignes comprises), chaque phrase
///   dans exactement une requête : rien de coupé ni de jeté en silence
///   (aujourd'hui `coachEnglish` ne garde que la fin) ;
/// - une partie en échec (injoignable, réponse illisible) ne fait pas tout
///   échouer : ses phrases sont notées non analysées, les autres corrections
///   restent ; si TOUTES échouent, l'erreur remonte (l'appelant l'affiche) ;
/// - chaque correction porte l'heure dans la note de la phrase qui contient
///   `original` (forme de réponse du modèle inchangée : il ne donne pas
///   d'heure ; introuvable = correction gardée, sans heure) ;
/// - les phrases déjà corrigées en direct ne repartent pas (arrêt entre
///   deux lots : coach_stop_between_batches_test.dart).
///
/// Pas de migration : l'heure et les phrases non analysées vivent dans le
/// JSON de `summaries.content` (enveloppe [SessionAnalysis]).
///
/// API supposée (à créer) :
/// - dans meeting_ai.dart :
///   `Future<EnglishFeedbackEntity> coachMeeting(llm, segments, {skipSegmentIds})`
///   (`LlmProvider`, `List<TranscriptSegmentEntity>`, `Set<String>`) ;
/// - `EnglishCorrectionEntity.timestampMs` (int?, ms depuis le début de la
///   note, comme `TranscriptSegmentEntity.timestampMs`) ;
/// - `EnglishFeedbackEntity.unanalyzedSegmentIds` (`List<String>`, défaut
///   vide) : ids des phrases dont la partie a échoué.
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

  String answer(List<Map<String, String>> corrections) => jsonEncode(
    <String, Object?>{'overall': 'Bon niveau.', 'corrections': corrections},
  );

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

  String allSent(ScriptedLlmProvider llm) =>
      llm.requests.map(requestText).join('\n');

  /// Réunion d'une heure : une phrase de l'utilisateur toutes les 5 s
  /// (720 phrases anglaises distinctes), une de l'interlocuteur entre deux.
  List<TranscriptSegmentEntity> hourLong() => <TranscriptSegmentEntity>[
    for (int i = 0; i < 720; i++) ...<TranscriptSegmentEntity>[
      seg(
        'me-$i',
        'Line $i: we need to check the figures for the next release.',
        atMs: i * 5000,
      ),
      seg(
        'them-$i',
        'Other $i: the budget is ready for the review.',
        atMs: i * 5000 + 2500,
        source: AudioSource.output,
      ),
    ],
  ];

  /// Ligne de l'utilisateur citée en premier dans [r] (« Line N: … »).
  String firstLineOf(LlmChatRequest r) {
    final RegExpMatch m = RegExp(
      r'Line (\d+): we need',
    ).firstMatch(requestText(r))!;
    return m.group(0)!;
  }

  group('ce qui part au modèle', () {
    test('seules les phrases du micro : ni l\'audio système, ni un repère de '
        'perte, ni « Passage non transcrit »', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));

      await coachMeeting(llm, <TranscriptSegmentEntity>[
        seg('a', 'I am agree with you on this point.', atMs: 0),
        seg(
          'b',
          'We need the budget by Friday.',
          atMs: 5000,
          source: AudioSource.output,
        ),
        seg(
          'c',
          LiveTranscriptionService.gapMarkerText(10000, 20000),
          atMs: 10000,
        ),
        seg(
          'd',
          LiveTranscriptionService.untranscribedMarkerText(30000, 34000),
          atMs: 30000,
        ),
        seg('e', 'He have sent the deck to the client.', atMs: 40000),
      ]);

      final String sent = allSent(llm);
      expect(sent, contains('I am agree with you on this point.'));
      expect(sent, contains('He have sent the deck to the client.'));
      expect(sent, isNot(contains('budget by Friday')));
      expect(sent, isNot(contains(LiveTranscriptionService.gapMarkerPrefix)));
      expect(sent, isNot(contains('Passage non transcrit')));
    });

    test(
      'une phrase de l\'utilisateur en français n\'est pas envoyée',
      () async {
        final ScriptedLlmProvider llm = replying(
          answer(<Map<String, String>>[]),
        );

        await coachMeeting(llm, <TranscriptSegmentEntity>[
          seg(
            'fr',
            'Je pense que le budget est validé pour la semaine.',
            atMs: 0,
          ),
          seg('en', 'We was ready for the demo yesterday.', atMs: 5000),
        ]);

        expect(allSent(llm), contains('We was ready for the demo yesterday.'));
        expect(allSent(llm), isNot(contains('le budget est validé')));
      },
    );

    test('phrase sans indice ou mêlée : anglaise seulement avec un mot-outil '
        'anglais et aucun français', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));
      const Map<String, bool> sent = <String, bool>{
        'I think so.': true,
        'OK.': false,
        'Yes exactly.': false,
        'Voilà.': false,
        'On fait le call with the team.': false,
      };
      int i = 0;

      await coachMeeting(llm, <TranscriptSegmentEntity>[
        for (final String text in sent.keys)
          seg('u-${i++}', text, atMs: i * 5000),
      ]);

      sent.forEach((String text, bool expected) {
        expect(
          allSent(llm).contains(text),
          expected,
          reason: '« $text » ${expected ? 'doit' : 'ne doit pas'} partir',
        );
      });
    });

    test('franglais que `questionLanguage` juge anglais : ignoré quand '
        'même (un mot-outil français suffit)', () async {
      const String franglais = 'On fait le call with the team.';
      expect(
        questionLanguage(franglais),
        'English',
        reason: 'prémisse : le seul juge de langue se tromperait ici',
      );
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));

      await coachMeeting(llm, <TranscriptSegmentEntity>[
        seg('mix', franglais, atMs: 0),
        seg('en', 'I am agree with you on this point.', atMs: 5000),
      ]);

      expect(allSent(llm), isNot(contains(franglais)));
      expect(
        allSent(llm),
        contains('I am agree with you on this point.'),
        reason: '« on » est des deux langues : ne compte pas comme français',
      );
    });

    test('rien que du français ou rien du micro : aucune requête, retour '
        'vide', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));

      final EnglishFeedbackEntity feedback =
          await coachMeeting(llm, <TranscriptSegmentEntity>[
            seg('fr', 'Je vous envoie le compte rendu de la réunion.', atMs: 0),
            seg(
              'them',
              'Can you share the slides with the team?',
              atMs: 5000,
              source: AudioSource.output,
            ),
          ]);

      expect(llm.requests, isEmpty);
      expect(feedback.corrections, isEmpty);
      expect(feedback.unanalyzedSegmentIds, isEmpty);
    });

    test('réunion de 60 minutes : plusieurs requêtes, chacune bornée, chaque '
        'phrase de l\'utilisateur dans exactement une', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));
      final List<TranscriptSegmentEntity> meeting = hourLong();

      await coachMeeting(llm, meeting);

      expect(llm.requests.length, greaterThan(1));
      for (final LlmChatRequest r in llm.requests) {
        expect(
          requestText(r).length,
          lessThanOrEqualTo(kLlmMaxRequestChars),
          reason: 'une requête dépasse la borne',
        );
      }
      for (final TranscriptSegmentEntity s in meeting) {
        if (s.source != AudioSource.input) continue;
        final int carrying = llm.requests
            .where((LlmChatRequest r) => requestText(r).contains(s.text))
            .length;
        expect(carrying, 1, reason: '« ${s.text} » envoyée $carrying fois');
      }
    });

    test('phrases déjà corrigées en direct : jamais renvoyées ; toutes '
        'corrigées : aucune requête', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));
      final List<TranscriptSegmentEntity> meeting = <TranscriptSegmentEntity>[
        seg('a', 'I am agree with you on this point.', atMs: 0),
        seg('b', 'He have sent the deck to the client.', atMs: 5000),
      ];

      await coachMeeting(llm, meeting, skipSegmentIds: <String>{'a'});
      expect(allSent(llm), isNot(contains('I am agree')));
      expect(allSent(llm), contains('He have sent the deck'));

      final ScriptedLlmProvider none = replying(
        answer(<Map<String, String>>[]),
      );
      await coachMeeting(none, meeting, skipSegmentIds: <String>{'a', 'b'});
      expect(none.requests, isEmpty);
    });
  });

  group('ce qui revient', () {
    test('chaque correction porte l\'heure, dans la note, de la phrase qui '
        'la contient', () async {
      final ScriptedLlmProvider llm = replying(
        answer(<Map<String, String>>[
          fix('He have sent', 'He has sent'),
          fix('I am agree', 'I agree'),
        ]),
      );

      final EnglishFeedbackEntity feedback =
          await coachMeeting(llm, <TranscriptSegmentEntity>[
            seg('a', 'I am agree with you on this point.', atMs: 65000),
            seg('b', 'He have sent the deck to the client.', atMs: 125000),
          ]);

      final Map<String, int?> timeOf = <String, int?>{
        for (final EnglishCorrectionEntity c in feedback.corrections)
          c.original: c.timestampMs,
      };
      expect(timeOf['I am agree'], 65000);
      expect(timeOf['He have sent'], 125000);
    });

    test(
      'correction introuvable dans les phrases : gardée, sans heure',
      () async {
        final ScriptedLlmProvider llm = replying(
          answer(<Map<String, String>>[
            fix('we discussed about', 'we discussed'),
          ]),
        );

        final EnglishFeedbackEntity feedback = await coachMeeting(
          llm,
          <TranscriptSegmentEntity>[
            seg('a', 'I am agree with you on this point.', atMs: 65000),
          ],
        );

        expect(feedback.corrections.single.corrected, 'we discussed');
        expect(feedback.corrections.single.timestampMs, isNull);
      },
    );

    test('le modèle dit en prose qu\'il n\'y a rien à corriger : aucune '
        'correction, rien de non analysé, pas d\'erreur', () async {
      for (final String prose in <String>[
        'No corrections needed.',
        'Your English is correct.',
        'Rien à corriger.',
        '[]',
      ]) {
        final ScriptedLlmProvider llm = replying(prose);

        final EnglishFeedbackEntity feedback = await coachMeeting(
          llm,
          <TranscriptSegmentEntity>[
            seg('a', 'I agree with you on this point.', atMs: 0),
          ],
        );

        expect(feedback.corrections, isEmpty, reason: prose);
        expect(feedback.unanalyzedSegmentIds, isEmpty, reason: prose);
      }
    });

    test('« aucune correction » : retour vide, rien de non analysé', () async {
      final ScriptedLlmProvider llm = replying(answer(<Map<String, String>>[]));

      final EnglishFeedbackEntity feedback = await coachMeeting(
        llm,
        <TranscriptSegmentEntity>[
          seg('a', 'I agree with you on this point.', atMs: 0),
        ],
      );

      expect(feedback.corrections, isEmpty);
      expect(feedback.unanalyzedSegmentIds, isEmpty);
    });
  });

  group('une partie échoue', () {
    for (final (String name, Stream<String> Function() failure)
        in <(String, Stream<String> Function())>[
          (
            'injoignable',
            () => Stream<String>.error(const LlmUnreachableException('Claude')),
          ),
          (
            'réponse illisible',
            () => Stream<String>.value('Désolé, je ne peux pas.'),
          ),
        ]) {
      test('$name : les autres corrections restent, les phrases de cette '
          'partie sont notées non analysées', () async {
        final ScriptedLlmProvider llm = ScriptedLlmProvider((
          LlmChatRequest r,
          int i,
        ) {
          if (i == 1) return failure();
          final String line = firstLineOf(r);
          return Stream<String>.value(
            answer(<Map<String, String>>[fix(line, '$line (corrigé)')]),
          );
        });
        final List<TranscriptSegmentEntity> meeting = hourLong();

        final EnglishFeedbackEntity feedback = await coachMeeting(llm, meeting);

        final String failed = requestText(llm.requests[1]);
        final Set<String> expectedIds = <String>{
          for (final TranscriptSegmentEntity s in meeting)
            if (s.source == AudioSource.input && failed.contains(s.text)) s.id,
        };
        expect(expectedIds, isNotEmpty);
        expect(feedback.unanalyzedSegmentIds.toSet(), expectedIds);
        expect(feedback.corrections, hasLength(llm.requests.length - 1));
        expect(
          feedback.corrections.map((EnglishCorrectionEntity c) => c.original),
          isNot(contains(firstLineOf(llm.requests[1]))),
        );
      });
    }

    test('toutes les parties échouent : l\'erreur remonte', () async {
      final ScriptedLlmProvider llm = ScriptedLlmProvider(
        (LlmChatRequest r, int i) =>
            Stream<String>.error(const LlmUnreachableException('Claude')),
      );

      await expectLater(
        coachMeeting(llm, <TranscriptSegmentEntity>[
          seg('a', 'I am agree with you on this point.', atMs: 0),
        ]),
        throwsA(isA<LlmUnreachableException>()),
      );
    });
  });

  group('enveloppe rangée (summaries.content, sans migration)', () {
    test('l\'heure des corrections et les phrases non analysées survivent '
        'à l\'aller-retour', () {
      const EnglishFeedbackEntity feedback = EnglishFeedbackEntity(
        corrections: <EnglishCorrectionEntity>[
          EnglishCorrectionEntity(
            original: 'I am agree',
            corrected: 'I agree',
            category: 'grammar',
            explanation: '« agree » est un verbe.',
            timestampMs: 65000,
          ),
        ],
        unanalyzedSegmentIds: <String>['me-12', 'me-13'],
      );

      final SessionAnalysis back = SessionAnalysis.fromStored(
        const SessionAnalysis(
          summary: 'Résumé.',
          feedback: feedback,
        ).toStored(),
      );

      expect(back.feedback, feedback);
      expect(back.summary, 'Résumé.');
    });

    test('enveloppe d\'avant (sans heure ni partie manquante) : se lit, '
        'sans heure, rien de non analysé', () {
      final String legacy = jsonEncode(<String, Object?>{
        'summary': null,
        'feedback': <String, Object?>{
          'overall': 'Bon niveau.',
          'corrections': <Map<String, String>>[
            <String, String>{
              'original': 'I am agree',
              'corrected': 'I agree',
              'category': 'grammar',
              'explanation': '« agree » est un verbe.',
            },
          ],
        },
        'micText': null,
        'speakers': <Object>[],
      });

      final EnglishFeedbackEntity? feedback = SessionAnalysis.fromStored(
        legacy,
      ).feedback;

      expect(feedback?.corrections.single.corrected, 'I agree');
      expect(feedback?.corrections.single.timestampMs, isNull);
      expect(feedback?.unanalyzedSegmentIds, isEmpty);
    });
  });
}
