import 'dart:async';

import 'package:core_data/database/dao/document.dao.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

import '../../../helpers/live_answers_fakes.dart';

/// Questions et réponses en direct (T4, besoins 2, 3, 4, 5, 6, 7, 8, 9, 10) :
/// la logique derrière des interfaces, sous horloge factice (fake_async).
///
/// API supposée (lib/application/services/live_answers/) :
/// - live_answers.service.dart :
///   `LiveAnswerModel({required LlmProvider provider, required String modelId})`
///   `typedef ExcerptSearch = Future<List<DocumentSearchResult>> Function(String query, {int limit})`
///   (même forme que `DocumentDao.search`).
///   `LiveAnswersService({required Future<LiveAnswerModel?> Function() resolveModel, required ExcerptSearch searchDocuments, required QuestionStore store})`
///   - `void start(String sessionId)`, `void pause()`, `void resume()`,
///     `Future<void> stop()`.
///   - `void onSegmentFinalized(TranscriptSegmentEntity segment, {int? speaker})`
///     : chaque segment FINAL des deux sources (contexte + porte).
///   - `void answerSegment(TranscriptSegmentEntity segment, {int? speaker})` :
///     « Répondre à cette phrase », sur n'importe quelle ligne.
///   - `void answerLatestFromOthers()` : « Répondre » à la dernière phrase des
///     autres participants, même si la porte n'a rien vu.
///   - `void retry(String questionId)`, `void dismiss(String questionId)`.
///   - `List<LiveQuestion> get questions` (ordre de détection) et
///     `Stream<List<LiveQuestion>> get questionsStream`.
///   - `resolveModel` est appelé à CHAQUE question (jamais mis en cache) ;
///     null = aucun modèle prêt.
/// - Constantes choisies : `kQuestionDedupeWindow` = 30 s,
///   `kDocumentSearchBudget` = 150 ms, `kContextWindow` = 3 min,
///   `kMaxContextChars` = 4000, `kMaxExcerpts` = 3 (limite passée à la
///   recherche), `kMaxExcerptChars` = 800.
/// - live_question.dart : `LiveQuestion` (id, sessionId, segmentId, text,
///   source, speaker, timestampMs, status, answer, truncated, failure,
///   sources, model), `enum LiveQuestionStatus { detected, answering,
///   answered, declined, failed, needsModel }`, `enum LiveAnswerFailure
///   { invalidKey, rateLimited, unreachable, malformed, other }`.
///
/// Choix faits ici (le besoin laissait le choix) :
/// - Une seule génération en vol par session ; une question arrivée pendant
///   ce temps attend dans UNE place (la plus récente gagne) ; celle qu'elle
///   remplace reste listée « détectée », sans réponse automatique, et peut
///   être lancée à la main (`retry`). La réponse en cours n'est jamais coupée.
/// - Les déclencheurs manuels passent par la même file.
/// - Fenêtres de temps (doublons, contexte) mesurées sur `timestampMs` (temps
///   de la réunion).
/// - « Ignorer » retire la question de la liste ET du stockage.
void main() {
  const String q = 'Est-ce que vous avez prévu une date de livraison ?';

  const DocumentSearchResult contract = DocumentSearchResult(
    chunkId: 'chunk-1',
    documentId: 'doc-contract',
    documentTitle: 'Contrat Acme 2026',
    content: 'EXCERPT-CONTRACT Livraison du lot 1 le 12 mars 2026.',
  );

  void run(
    void Function(FakeAsync async, LiveAnswersHarness h) body, {
    bool modelReady = true,
  }) {
    fakeAsync((FakeAsync async) {
      final LiveAnswersHarness h = LiveAnswersHarness(modelReady: modelReady);
      body(async, h);
      async.flushMicrotasks();
    });
  }

  group('détection et départ immédiat (latence)', () {
    test('une question des autres lance UNE requête en flux, sans délai '
        '(aucun temps écoulé)', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        expect(h.llm.requests, hasLength(1));
        expect(async.elapsed, Duration.zero);
        expect(h.only.text, q);
        expect(h.only.status, LiveQuestionStatus.answering);
      });
    });

    test('la recherche de documents part tout de suite, sur les mots de la '
        'question, limitée aux meilleurs extraits', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        expect(h.search.calls, hasLength(1));
        expect(h.search.calls.single.query, contains('livraison'));
        expect(h.search.calls.single.query, contains('date'));
        expect(h.search.calls.single.limit, kMaxExcerpts);
      });
    });

    test('recherche plus lente que le budget : la requête part au budget, '
        'sans extrait, et le résultat tardif est ignoré', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        final Completer<List<DocumentSearchResult>> slow =
            Completer<List<DocumentSearchResult>>();
        h.search.pending = () => slow.future;

        h.hear(q);
        async.elapse(kDocumentSearchBudget - const Duration(milliseconds: 1));
        expect(h.llm.requests, isEmpty, reason: 'avant le budget');

        async.elapse(const Duration(milliseconds: 1));
        expect(h.llm.requests, hasLength(1));
        expect(requestText(h.llm.last.request), isNot(contains('EXCERPT-')));

        slow.complete(<DocumentSearchResult>[contract]);
        async.flushMicrotasks();
        h.llm.last.reply('Le lot 1 arrive le 12 mars [S1].');
        async.flushMicrotasks();

        expect(h.llm.requests, hasLength(1), reason: 'pas de 2e requête');
        expect(h.only.sources, isEmpty);
      });
    });

    test('recherche dans le budget : la requête l\'attend et porte les '
        'extraits', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.search.pending = () => Future<List<DocumentSearchResult>>.delayed(
          const Duration(milliseconds: 100),
          () => <DocumentSearchResult>[contract],
        );

        h.hear(q);
        async.elapse(const Duration(milliseconds: 99));
        expect(h.llm.requests, isEmpty);
        async.elapse(const Duration(milliseconds: 1));

        expect(h.llm.requests, hasLength(1));
        expect(requestText(h.llm.last.request), contains('EXCERPT-CONTRACT'));
      });
    });

    test(
      'recherche en échec : la requête part sans extrait, pas d\'erreur',
      () {
        run((FakeAsync async, LiveAnswersHarness h) {
          h.search.pending = () =>
              Future<List<DocumentSearchResult>>.error(StateError('fts'));

          h.hear(q);
          async.flushMicrotasks();

          expect(h.llm.requests, hasLength(1));
          expect(h.only.status, LiveQuestionStatus.answering);
        });
      },
    );

    test('une question de l\'utilisateur (micro) ne déclenche rien', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, source: AudioSource.input, speaker: null);
        async.elapse(const Duration(seconds: 1));

        expect(h.questions, isEmpty);
        expect(h.llm.requests, isEmpty);
      });
    });

    test('une affirmation des autres ne déclenche rien', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear('On livre le lot 1 en mars.');
        async.elapse(const Duration(seconds: 1));

        expect(h.questions, isEmpty);
        expect(h.llm.requests, isEmpty);
        expect(h.search.calls, isEmpty);
      });
    });

    test('seule la phrase-question d\'un segment devient la question', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear('Merci pour la démo. Quel est le prix du module RH ?');
        async.flushMicrotasks();

        expect(h.only.text, 'Quel est le prix du module RH ?');
      });
    });
  });

  group('requête envoyée au modèle', () {
    test('contient la question dans le dernier message utilisateur', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        final LlmChatRequest r = h.llm.last.request;
        expect(r.systemPrompt.trim(), isNotEmpty);
        expect(r.messages.last.role, LlmRole.user);
        expect(r.messages.last.content, contains(q));
      });
    });

    test('contient le contexte récent des deux sources, avec qui parle', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h
          ..hear(
            'CTX-MIC on a fini la recette.',
            source: AudioSource.input,
            speaker: null,
            atMs: 50000,
          )
          ..hear('CTX-SYS-A le budget est validé.', speaker: 0, atMs: 52000)
          ..hear('CTX-SYS-B la recette est finie.', speaker: 1, atMs: 55000)
          ..hear(q, speaker: 1, atMs: 60000);
        async.flushMicrotasks();

        final List<String> lines = requestText(h.llm.last.request).split('\n');
        String lineOf(String tag) =>
            lines.firstWhere((String l) => l.contains(tag));
        String labelOf(String tag) =>
            lineOf(tag).substring(0, lineOf(tag).indexOf(tag)).trim();

        for (final String tag in <String>[
          'CTX-MIC',
          'CTX-SYS-A',
          'CTX-SYS-B',
        ]) {
          expect(labelOf(tag), isNotEmpty, reason: '$tag sans locuteur');
        }
        expect(labelOf('CTX-MIC'), isNot(labelOf('CTX-SYS-A')));
        expect(labelOf('CTX-SYS-A'), isNot(labelOf('CTX-SYS-B')));
      });
    });

    test('ne contient pas ce qui a été dit avant la fenêtre de contexte', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        const int qAt = 10 * 60 * 1000;
        h
          ..hear(
            'CTX-OLD au début de la réunion.',
            atMs: qAt - kContextWindow.inMilliseconds - 1000,
          )
          ..hear('CTX-RECENT juste avant.', atMs: qAt - 5000)
          ..hear(q, atMs: qAt);
        async.flushMicrotasks();

        final String text = requestText(h.llm.last.request);
        expect(text, contains('CTX-RECENT'));
        expect(text, isNot(contains('CTX-OLD')));
      });
    });

    test('contexte borné en caractères : garde le plus récent', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        for (int i = 0; i < 200; i++) {
          final String tag = 'CTX-${i.toString().padLeft(3, '0')}';
          h.hear(
            '$tag ${'x' * 90}.',
            source: i.isEven ? AudioSource.input : AudioSource.output,
            speaker: i.isEven ? null : 1,
            atMs: 60000 + i * 500,
          );
        }
        h.hear(q, atMs: 60000 + 200 * 500);
        async.flushMicrotasks();

        final String text = requestText(h.llm.last.request);
        expect(text, contains('CTX-199'));
        expect(text, isNot(contains('CTX-000')));
        final int kept = 'CTX-'.allMatches(text).length;
        expect(kept * 95, lessThanOrEqualTo(kMaxContextChars));
      });
    });

    test('porte les extraits : titre, contenu et repère [S1], [S2]…', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.search.results = <DocumentSearchResult>[
          contract,
          const DocumentSearchResult(
            chunkId: 'chunk-2',
            documentId: 'doc-pricing',
            documentTitle: 'Grille tarifaire',
            content: 'EXCERPT-PRICING 40 € par utilisateur.',
          ),
        ];
        h.hear(q);
        async.flushMicrotasks();

        final String text = requestText(h.llm.last.request);
        expect(text, contains('Contrat Acme 2026'));
        expect(text, contains('EXCERPT-CONTRACT'));
        expect(text, contains('Grille tarifaire'));
        expect(text, contains('EXCERPT-PRICING'));
        expect(text, contains('[S1]'));
        expect(text, contains('[S2]'));
      });
    });

    test('jamais un document entier : extrait long coupé, au plus '
        'kMaxExcerpts extraits', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.search.results = <DocumentSearchResult>[
          DocumentSearchResult(
            chunkId: 'big',
            documentId: 'doc-big',
            documentTitle: 'Gros manuel',
            content: 'EXCERPT-HEAD ${'y' * 5000} EXCERPT-TAIL',
          ),
          for (int i = 0; i < 4; i++)
            DocumentSearchResult(
              chunkId: 'c$i',
              documentId: 'd$i',
              documentTitle: 'Doc $i',
              content: 'EXCERPT-N$i',
            ),
        ];
        h.hear(q);
        async.flushMicrotasks();

        final String text = requestText(h.llm.last.request);
        expect(text, contains('EXCERPT-HEAD'));
        expect(text, isNot(contains('EXCERPT-TAIL')));
        expect(
          'EXCERPT-'.allMatches(text).length,
          lessThanOrEqualTo(kMaxExcerpts),
        );
        expect(text.length, lessThan(5000 + kMaxContextChars));
      });
    });
  });

  group('flux et états', () {
    test('le premier morceau s\'affiche dès son arrivée, puis grandit', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        h.llm.last.delta('La livraison');
        async.flushMicrotasks();
        expect(h.only.status, LiveQuestionStatus.answering);
        expect(h.only.answer, 'La livraison');

        h.llm.last.delta(' est prévue le 12 mars.');
        async.flushMicrotasks();
        expect(h.only.answer, 'La livraison est prévue le 12 mars.');
      });
    });

    test('le flux de questions publie l\'état partiel (l\'écran le voit)', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        final List<List<LiveQuestion>> seen = <List<LiveQuestion>>[];
        h.service.questionsStream.listen(seen.add);
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.delta('La livraison');
        async.flushMicrotasks();

        expect(
          seen.any(
            (List<LiveQuestion> l) =>
                l.length == 1 &&
                l.single.status == LiveQuestionStatus.answering &&
                l.single.answer == 'La livraison',
          ),
          isTrue,
        );
      });
    });

    test('fin du flux : répondue, avec le modèle utilisé', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.reply('La livraison est prévue le 12 mars.');
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.answered);
        expect(h.only.answer, 'La livraison est prévue le 12 mars.');
        expect(h.only.model, 'claude-haiku-5-5');
        expect(h.only.truncated, isFalse);
      });
    });

    test('au plus trois puces gardées', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.reply('Oui.\n- un.\n- deux.\n- trois.\n- QUATRE.');
        async.flushMicrotasks();

        expect(h.only.answer, isNot(contains('QUATRE')));
      });
    });

    test('citations : seules celles vers un extrait fourni deviennent des '
        'sources', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.search.results = <DocumentSearchResult>[contract];
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.reply(
          'Le lot 1 arrive le 12 mars [S1], le lot 2 en avril [S4].',
        );
        async.flushMicrotasks();

        expect(h.only.sources, <AnswerSource>[
          AnswerSource(
            documentId: contract.documentId,
            title: contract.documentTitle,
            excerpt: contract.content,
          ),
        ]);
        expect(h.only.answer, isNot(contains('[S4]')));
      });
    });

    test('réponse coupée (fin sans erreur au milieu d\'une phrase) : montrée '
        'telle quelle, marquée tronquée', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.reply(
          'La livraison est prévue pour le lot 1 au début du mo',
        );
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.answered);
        expect(h.only.truncated, isTrue);
        expect(
          h.only.answer,
          'La livraison est prévue pour le lot 1 au début du mo',
        );
      });
    });

    test('refus du modèle (NO_ANSWER) : rien d\'affiché, question gardée et '
        'marquée refusée', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.delta('NO_');
        async.flushMicrotasks();
        expect(
          h.only.answer,
          isNot(contains('NO_')),
          reason: 'le jeton réservé ne s\'affiche jamais, même en partie',
        );

        h.llm.last
          ..delta('ANSWER')
          ..end();
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.declined);
        expect(h.only.answer, isEmpty);
        expect(h.only.text, q);
      });
    });

    test('une vraie réponse qui commence comme le jeton s\'affiche dès '
        'qu\'elle en diffère', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.delta('Non, pas');
        async.flushMicrotasks();

        expect(h.only.answer, 'Non, pas');
      });
    });

    final Map<Object, LiveAnswerFailure> errors = <Object, LiveAnswerFailure>{
      const LlmInvalidKeyException('anthropic'): LiveAnswerFailure.invalidKey,
      const LlmRateLimitedException('openai'): LiveAnswerFailure.rateLimited,
      const LlmUnreachableException('gemini'): LiveAnswerFailure.unreachable,
      const FormatException('ligne JSON invalide'): LiveAnswerFailure.malformed,
      const LlmException('autre'): LiveAnswerFailure.other,
    };
    errors.forEach((Object error, LiveAnswerFailure reason) {
      test(
        '${error.runtimeType} → échec « ${reason.name} », sans plantage',
        () {
          run((FakeAsync async, LiveAnswersHarness h) {
            h.hear(q);
            async.flushMicrotasks();
            h.llm.last
              ..delta('La livr')
              ..fail(error);
            async.flushMicrotasks();

            expect(h.only.status, LiveQuestionStatus.failed);
            expect(h.only.failure, reason);
          });
        },
      );
    });

    test('une question en échec se relance à la main : nouvelle requête, '
        'seulement le nouveau texte', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last
          ..delta('Début perdu')
          ..fail(const LlmUnreachableException('anthropic'));
        async.flushMicrotasks();

        h.service.retry(h.only.id);
        async.flushMicrotasks();
        expect(h.llm.requests, hasLength(2));
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.answered);
        expect(h.only.answer, 'Le 12 mars.');
        expect(h.only.failure, isNull);
      });
    });
  });

  group('doublons et cadence', () {
    test('la même question répétée dans la fenêtre : traitée une fois', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();
        h.hear(q, atMs: 60000 + kQuestionDedupeWindow.inMilliseconds - 1000);
        async.flushMicrotasks();

        expect(h.questions, hasLength(1));
        expect(h.llm.requests, hasLength(1));
      });
    });

    for (final String variant in <String>[
      'est-ce que vous avez prévu une date de livraison',
      'Est-ce que vous avez prevu une date de livraison ?',
      'Donc, est-ce que vous avez prévu une date de livraison ?',
    ]) {
      test(
        'quasi identique « $variant » dans la fenêtre : traitée une fois',
        () {
          run((FakeAsync async, LiveAnswersHarness h) {
            h.hear(q, atMs: 60000);
            async.flushMicrotasks();
            h.llm.last.reply('Le 12 mars.');
            async.flushMicrotasks();
            h.hear(variant, atMs: 70000);
            async.flushMicrotasks();

            expect(h.questions, hasLength(1));
            expect(h.llm.requests, hasLength(1));
          });
        },
      );
    }

    test('la même question après la fenêtre : traitée à nouveau', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();
        h.hear(q, atMs: 60000 + kQuestionDedupeWindow.inMilliseconds + 1000);
        async.flushMicrotasks();

        expect(h.questions, hasLength(2));
        expect(h.llm.requests, hasLength(2));
      });
    });

    test('une autre question dans la fenêtre : traitée', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 65000);
        async.flushMicrotasks();

        expect(h.questions, hasLength(2));
      });
    });

    test('une seule génération en vol : la question suivante attend la fin '
        'de la réponse en cours', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 62000);
        async.flushMicrotasks();

        expect(h.llm.requests, hasLength(1));
        expect(h.questions, hasLength(2));
        expect(h.questions[1].status, LiveQuestionStatus.detected);
        expect(
          h.llm.last.cancelled,
          isFalse,
          reason: 'réponse en cours gardée',
        );

        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();

        expect(h.llm.requests, hasLength(2));
        expect(
          h.llm.last.request.messages.last.content,
          contains('Combien coûte la licence'),
        );
      });
    });

    test('file d\'une place, la plus récente gagne ; l\'autre reste listée '
        'et se lance à la main', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        const String b = 'Combien coûte la licence par utilisateur ?';
        const String c = 'Où sont hébergés les serveurs ?';
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h
          ..hear(b, atMs: 61000)
          ..hear(c, atMs: 62000);
        async.flushMicrotasks();

        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();
        expect(h.llm.requests, hasLength(2));
        expect(h.llm.last.request.messages.last.content, contains(c));

        h.llm.last.reply('En France.');
        async.flushMicrotasks();
        expect(h.llm.requests, hasLength(2), reason: 'b jamais lancée seule');
        final LiveQuestion qb = h.questions.firstWhere(
          (LiveQuestion x) => x.text == b,
        );
        expect(qb.status, LiveQuestionStatus.detected);

        h.service.retry(qb.id);
        async.flushMicrotasks();
        expect(h.llm.requests, hasLength(3));
        expect(h.llm.last.request.messages.last.content, contains(b));
      });
    });

    test('en pause : rien n\'est détecté ; à la reprise, si', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.service.pause();
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        expect(h.questions, isEmpty);
        expect(h.llm.requests, isEmpty);

        h.service.resume();
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 90000);
        async.flushMicrotasks();
        expect(h.questions, hasLength(1));
      });
    });

    test('session arrêtée : rien n\'est détecté', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        unawaited(h.service.stop());
        async.flushMicrotasks();
        h.hear(q);
        async.flushMicrotasks();

        expect(h.questions.where((LiveQuestion x) => x.text == q), isEmpty);
        expect(h.llm.requests, isEmpty);
      });
    });
  });

  group('annulation', () {
    test('arrêter la session annule la requête en vol', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.delta('La livr');
        async.flushMicrotasks();

        unawaited(h.service.stop());
        async.flushMicrotasks();

        expect(h.llm.last.cancelled, isTrue);
        expect(
          h.store.log.where((String l) => l.startsWith('answer:')),
          isEmpty,
        );
      });
    });

    test('ignorer une question en vol annule sa requête, la retire, et la '
        'question en attente part', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 62000);
        async.flushMicrotasks();
        final ScriptedStream first = h.llm.last;
        final String id = h.questions.first.id;

        h.service.dismiss(id);
        async.flushMicrotasks();

        expect(first.cancelled, isTrue);
        expect(h.questions.map((LiveQuestion x) => x.id), isNot(contains(id)));
        expect(h.store.saved.containsKey(id), isFalse);
        expect(h.llm.requests, hasLength(2));
      });
    });

    test('ignorer une question répondue la retire de la liste', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();

        h.service.dismiss(h.only.id);
        async.flushMicrotasks();

        expect(h.questions, isEmpty);
      });
    });
  });

  group('déclencheurs manuels', () {
    test('« Répondre à cette phrase » sur une ligne de l\'utilisateur : la '
        'phrase devient une question et part', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        final TranscriptSegmentEntity s = h.segment(
          'Je me demande si on peut livrer en mars.',
          source: AudioSource.input,
        );
        h.service.answerSegment(s);
        async.flushMicrotasks();

        expect(h.only.text, 'Je me demande si on peut livrer en mars.');
        expect(h.only.segmentId, s.id);
        expect(h.only.source, AudioSource.input);
        expect(h.llm.requests, hasLength(1));
      });
    });

    test('« Répondre » répond à la dernière phrase des autres, même si la '
        'porte n\'a rien vu, pas à celle de l\'utilisateur', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h
          ..hear('On aimerait une livraison en mars.', atMs: 60000)
          ..hear(
            'Moi je note.',
            source: AudioSource.input,
            speaker: null,
            atMs: 61000,
          );
        async.flushMicrotasks();
        expect(h.questions, isEmpty);

        h.service.answerLatestFromOthers();
        async.flushMicrotasks();

        expect(h.only.text, 'On aimerait une livraison en mars.');
        expect(h.only.speaker, 1);
        expect(h.llm.requests, hasLength(1));
      });
    });

    test('« Répondre » sans aucune phrase des autres : rien', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear('Moi je note.', source: AudioSource.input, speaker: null);
        h.service.answerLatestFromOthers();
        async.flushMicrotasks();

        expect(h.questions, isEmpty);
        expect(h.llm.requests, isEmpty);
      });
    });
  });

  group('aucun modèle prêt (envoi coupé et modèle local absent)', () {
    test('la question est quand même détectée, listée et sauvée, état '
        '« configurer un modèle », rien n\'est envoyé', () {
      run(modelReady: false, (FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.needsModel);
        expect(h.llm.requests, isEmpty);
        expect(h.store.saved[h.only.id]?.text, q);
      });
    });

    test('modèle configuré ensuite : « Réessayer » répond', () {
      run(modelReady: false, (FakeAsync async, LiveAnswersHarness h) {
        h.hear(q);
        async.flushMicrotasks();

        h.modelReady = true;
        h.service.retry(h.only.id);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();

        expect(h.only.status, LiveQuestionStatus.answered);
      });
    });

    test('le modèle est résolu à chaque question (un changement de '
        'Réglages compte dès la suivante)', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.llm.last.reply('Le 12 mars.');
        async.flushMicrotasks();

        h.modelReady = false;
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 65000);
        async.flushMicrotasks();

        expect(h.resolveCalls, 2);
        expect(h.questions.last.status, LiveQuestionStatus.needsModel);
        expect(h.llm.requests, hasLength(1));
      });
    });
  });

  group('sauvegarde', () {
    test('la question est sauvée dès sa détection, avec son segment et son '
        'heure, avant la réponse', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        final TranscriptSegmentEntity s = h.hear(q, atMs: 65000);
        async.flushMicrotasks();

        final LiveQuestion? saved = h.store.saved[h.only.id];
        expect(saved, isNotNull);
        expect(saved!.sessionId, 's1');
        expect(saved.segmentId, s.id);
        expect(saved.timestampMs, 65000);
        expect(saved.text, q);
        expect(h.store.log, <String>['detected:${h.only.id}']);
      });
    });

    test('à la fin du flux : réponse, modèle et sources sauvés', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.search.results = <DocumentSearchResult>[contract];
        h.hear(q);
        async.flushMicrotasks();
        h.llm.last
          ..delta('Le lot 1 arrive ')
          ..delta('le 12 mars [S1].');
        async.flushMicrotasks();
        expect(
          h.store.log.where((String l) => l.startsWith('answer:')),
          isEmpty,
          reason: 'rien sauvé tant que le flux n\'est pas fini',
        );
        h.llm.last.end();
        async.flushMicrotasks();

        final LiveQuestion saved = h.store.saved[h.only.id]!;
        expect(saved.answer, contains('Le lot 1 arrive le 12 mars'));
        expect(saved.model, 'claude-haiku-5-5');
        expect(saved.sources.single.documentId, 'doc-contract');
      });
    });

    test('refus ou échec : la question reste sauvée, sans réponse', () {
      run((FakeAsync async, LiveAnswersHarness h) {
        h.hear(q, atMs: 60000);
        async.flushMicrotasks();
        h.llm.last.reply(kNoAnswerToken);
        async.flushMicrotasks();
        h.hear('Combien coûte la licence par utilisateur ?', atMs: 65000);
        async.flushMicrotasks();
        h.llm.last.fail(const FormatException('x'));
        async.flushMicrotasks();

        expect(h.store.saved, hasLength(2));
        for (final LiveQuestion saved in h.store.saved.values) {
          expect(saved.answer, isEmpty);
        }
        expect(
          h.store.log.where((String l) => l.startsWith('answer:')),
          isEmpty,
        );
      });
    });
  });
}
