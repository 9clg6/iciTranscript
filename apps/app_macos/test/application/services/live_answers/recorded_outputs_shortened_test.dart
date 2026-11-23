import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

import '../../../helpers/probe_outputs.dart';

/// (Suite de recorded_outputs_test.dart : raccourcissement, API nouvelle.)
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

  group('4. plus de trois puces', () {
    for (final String key in <String>[
      'contract/fr1-c#0',
      'contract/fr2-d#0',
      'contract/en2-d#0',
      'contract/en2-d#2',
    ]) {
      test('$key : plus de trois puces : tête + trois puces, raccourcie, '
          'avec sa tête', () {
        final ParsedAnswer a = parse(key);
        expect(a.declined, isFalse);
        expect(a.headline, isNotEmpty);
        expect(a.bullets, hasLength(kMaxBullets));
        expect(a.shortened, isTrue);
      });
    }

    test('contract/en3-a#1 : la réponse (13 mois, [S3]) est dans le 3e bloc : '
        'c\'est ce bloc qui est gardé, raccourci', () {
      final ParsedAnswer a = parse('contract/en3-a#1');
      expect(a.text, contains('13 months'));
      expect(a.sources.map((AnswerSource s) => s.title), <String>[
        'Data retention policy',
      ]);
      expect(a.shortened, isTrue);
      expect(a.bullets.length, lessThanOrEqualTo(kMaxBullets));
    });

    test('réponse courte : pas raccourcie', () {
      expect(parse('contract/en1-a1#0').shortened, isFalse);
      expect(parse('contract/fr1-a2#0').shortened, isFalse);
    });
  });
}
