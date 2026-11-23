import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

import '../../../helpers/probe_outputs.dart';

/// Sorties RÉELLES d'un modèle local (mistral 7B, 96 générations de la
/// sonde, contenu inventé), lues par `parseAnswer` avec les extraits que le
/// modèle avait reçus. Le modèle n'a jamais émis `NO_ANSWER` seul, refuse en
/// prose, cite dans de mauvais formats, ajoute des préambules et dépasse les
/// trois puces.
///
/// API supposée (answer_parser.dart, en plus de PR #20) :
/// - `ParsedAnswer.declined` couvre aussi le refus en prose et le jeton au
///   milieu du texte (même état que `NO_ANSWER`).
/// - `ParsedAnswer.shortened` (bool) : des lignes reçues ne sont pas
///   montrées (au-delà de la tête et de trois puces) ; l'écran le dit.
/// - Citations : dans `text`, seules des marques canoniques `[S<n>]` vers un
///   extrait fourni, reportées dans `sources`.
///
/// Règles choisies :
/// - Refus en prose : la phrase qui répond dit que l'information manque
///   (« not (explicitly) given/provided/stated/indicated/mentioned/
///   specified », « the documents/excerpts do not mention/contain », « the
///   user did not specify », « no specific information/cost … given/
///   available », « n'est pas donné/indiqué/précisé/mentionné », « n'ont pas
///   été mentionnés », « non spécifié/indiqué/précisé », « ne connaît pas »,
///   « aucune information ») ou que le texte n'est pas une question pour
///   l'utilisateur (« the question is a comment, not a question »). La phrase
///   qui répond = la première phrase de la tête ; si la tête est un titre
///   (sans ponctuation finale, ou finie par « : », suivi de puces), toute
///   ligne compte. Un état du monde (« not yet approved », « yet to be
///   confirmed », « does not include ») reste une réponse.
/// - Jeton `NO_ANSWER` (avec ou sans crochets) ailleurs qu'en tête : la ligne
///   qui le porte est retirée ; s'il ne reste rien de substantiel (seulement
///   un préambule ou une remarque « pas une question »), c'est un refus.
/// - Groupe entre crochets ou parenthèses qui contient des tags `S<n>` et/ou
///   des heures (`[S1, S4]`, `[02:23 S1]`, `([S1])`, `[S1: 00:00:39]`) et
///   « document S1 » : remplacés par les `[S<n>]` fournis, le reste retiré ;
///   heures seules (`[00:00:52]`, `[S0:00:13]`, `[User, 00:02:36]`,
///   `(User, 00:00:01)`) : retirées.
/// - Préambule (« User's response: », « User: », « Answer: », « Response: »,
///   « Réponse : ») : retiré, jamais pris pour la tête.
/// - Plus de trois puces : tête + trois puces (les lignes suivantes, puces
///   ou non), `shortened`. Si la sortie a plusieurs blocs (séparés par une
///   ligne vide, chacun commençant par une ligne qui n'est pas une puce), le
///   bloc gardé est le premier qui cite un extrait fourni, sinon le premier.
/// - Tronquée : seulement si la dernière ligne finit sur un signe de suite,
///   un mot outil, une parenthèse ouverte ou une puce vide ; une dernière
///   ligne sans point final n'est pas tronquée (pas de signal de longueur du
///   fournisseur).
void main() {
  ParsedAnswer parse(String key) {
    final ProbeOutput o = probe(key);
    return parseAnswer(o.raw, o.excerpts);
  }

  group('1. refus en prose : même état que NO_ANSWER', () {
    for (final String key in <String>[
      'contract/fr3-c#0',
      'contract/fr3-d#0',
      'contract/en2-c#0',
      'contract/en3-c#0',
      'contract/fr3-c#1',
      'contract/en2-c#1',
      'contract/fr3-c#2',
      'contract/en2-c#2',
      'contract/en3-c#2',
      'clean/fr1-c#0',
      'clean/en3-c#0',
      'contract/fr2-d#2',
    ]) {
      test('$key : refus, rien d\'affiché', () {
        final ParsedAnswer a = parse(key);
        expect(a.declined, isTrue, reason: probe(key).raw);
        expect(a.text, isEmpty);
        expect(a.sources, isEmpty);
      });
    }

    for (final String key in <String>[
      // Réponses qui contiennent une négation : elles restent des réponses.
      'contract/en2-a#1',
      'contract/fr3-b#2',
      'clean/fr1-a2#0',
      'contract/en1-c#0',
      'contract/en1-c#2',
      'clean/en1-c#0',
      'contract/fr1-c#2',
      'contract/en3-c#1',
      // Réponses simples.
      'contract/en1-a1#0',
      'contract/fr1-a2#2',
      'clean/fr3-a#0',
      'contract/en3-a#0',
      'contract/fr3-b#0',
    ]) {
      test('$key : reste une réponse', () {
        final ParsedAnswer a = parse(key);
        expect(a.declined, isFalse, reason: probe(key).raw);
        expect(a.headline, isNotEmpty);
      });
    }
  });

  group('2. NO_ANSWER au milieu du texte : jamais affiché', () {
    test('contract/fr3-b#1 : réponse avant le jeton, la ligne du jeton est '
        'retirée', () {
      final ParsedAnswer a = parse('contract/fr3-b#1');
      expect(a.declined, isFalse);
      expect(a.text, contains('18 tickets'));
      expect(a.text, isNot(contains('NO_ANSWER')));
      expect(a.text, isNot(contains('No new tickets were answered')));
    });

    test('clean/fr3-b#0 : idem, la phrase finale qui porte le jeton part', () {
      final ParsedAnswer a = parse('clean/fr3-b#0');
      expect(a.declined, isFalse);
      expect(a.text, contains('18 tickets'));
      expect(a.text, isNot(contains('NO_ANSWER')));
      expect(a.text, isNot(contains('15 tickets')));
    });

    test('clean/fr2-d#0 : seulement une remarque « pas une question » avant '
        'le jeton (sans crochets) : refus', () {
      final ParsedAnswer a = parse('clean/fr2-d#0');
      expect(a.declined, isTrue);
      expect(a.text, isEmpty);
    });
  });

  group('3. nettoyage avant affichage', () {
    for (final (String key, String expected) in <(String, String)>[
      (
        'contract/en3-b#0',
        'Two engineers are assigned to the warehouse migration full time.',
      ),
      (
        'contract/en2-b#1',
        'Average first response time last month was four hours.',
      ),
    ]) {
      test('$key : heure en guise de citation retirée', () {
        final ParsedAnswer a = parse(key);
        expect(a.text, expected);
        expect(a.sources, isEmpty);
      });
    }

    test('contract/fr2-b#2 et contract/en2-b#2 : « [User, 00:02:36] », '
        '« (User, 00:00:01) » retirés', () {
      expect(parse('contract/fr2-b#2').text, isNot(contains('00:02:36')));
      final ParsedAnswer b = parse('contract/en2-b#2');
      expect(b.text, isNot(contains('00:00:01')));
      expect(b.text, isNot(contains('(User')));
    });

    test('contract/en3-d#1 : liste d\'heures retirée', () {
      expect(parse('contract/en3-d#1').text, isNot(contains('00:00:')));
    });

    test(
      'contract/fr3-d#1 : « [S1, S4] » sans aucun extrait fourni : retiré',
      () {
        final ParsedAnswer a = parse('contract/fr3-d#1');
        expect(a.text, isNot(contains('S1')));
        expect(a.text, isNot(contains('S4')));
        expect(a.sources, isEmpty);
      },
    );

    test('contract/fr2-c#0 : « document S1 » devient la citation [S1] de '
        'l\'extrait fourni', () {
      final ParsedAnswer a = parse('contract/fr2-c#0');
      expect(a.text, isNot(contains('document S1')));
      expect(a.text, contains('[S1]'));
      expect(a.sources.map((AnswerSource s) => s.title), <String>[
        'Informations du gîte',
      ]);
    });

    test(
      'contract/fr1-c#2 : « ([S1]) » devient [S1], sans parenthèses vides',
      () {
        final ParsedAnswer a = parse('contract/fr1-c#2');
        expect(a.text, isNot(contains('(')));
        expect(a.text, contains('[S1]'));
        expect(a.sources.map((AnswerSource s) => s.title), <String>[
          'Planning du projet',
        ]);
      },
    );

    test('cold/en1-b#2 : « [02:23 S1] » devient [S1] ; le préambule « User\'s '
        'response: » n\'est pas la tête', () {
      final ParsedAnswer a = parse('cold/en1-b#2');
      expect(
        a.headline,
        'The new building provides twenty-five parking spaces. [S1]',
      );
      expect(a.sources.map((AnswerSource s) => s.title), <String>[
        'Floor plan notes',
      ]);
    });

    test('contract/en1-b#0 : « User\'s response: » sur sa ligne : retiré', () {
      expect(
        parse('contract/en1-b#0').headline,
        'The new building offers 25 parking spaces. [S1]',
      );
    });

    test('clean/en1-b#0 : « User: » en tête de ligne retiré ; [S2] non '
        'fourni retiré', () {
      final ParsedAnswer a = parse('clean/en1-b#0');
      expect(a.headline, 'The new building has 25 parking spaces.');
      expect(a.sources, isEmpty);
    });

    for (final String raw in <String>[
      'Answer: The notice period is 90 days [S1].',
      'Réponse : Le préavis est de 90 jours [S1].',
      'Réponse :\nLe préavis est de 90 jours [S1].',
    ]) {
      test(
        'préambule « ${raw.split(':').first} : » jamais pris pour la tête',
        () {
          final ParsedAnswer a = parseAnswer(
            raw,
            probe('contract/fr1-a1#0').excerpts,
          );
          expect(a.headline, isNot(startsWith('Answer')));
          expect(a.headline, isNot(startsWith('Réponse')));
          expect(a.headline, contains('90'));
        },
      );
    }

    test('contract/fr2-b#0 : citations [S3], [S39] sans extrait fourni : '
        'retirées', () {
      final ParsedAnswer a = parse('contract/fr2-b#0');
      expect(a.text, isNot(contains('[S')));
      expect(a.sources, isEmpty);
    });
  });

  group('4. troncature', () {
    for (final String key in <String>[
      'contract/fr1-b#0',
      'contract/en3-b#0',
      'contract/en3-b#1',
      'contract/en2-b#1',
    ]) {
      test('$key : dernière ligne sans point final : PAS tronquée', () {
        expect(parse(key).truncated, isFalse, reason: probe(key).raw);
      });
    }
  });
}
