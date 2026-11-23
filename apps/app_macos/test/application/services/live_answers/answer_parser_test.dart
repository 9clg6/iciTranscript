import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

/// Contrat de sortie d'une réponse proposée (T4, besoin 4) : une phrase de
/// tête, au plus trois puces, des sources qui existent vraiment, un refus
/// explicite du modèle. Fonction pure, appliquée au texte complet reçu.
///
/// API supposée :
/// - lib/application/services/live_answers/answer_parser.dart :
///   `ParsedAnswer parseAnswer(String raw, List<DocumentExcerpt> excerpts)`
///   avec `ParsedAnswer` : `bool declined`, `String headline`,
///   `List<String> bullets` (sans leur marqueur « - », « • », « * »),
///   `List<AnswerSource> sources`, `bool truncated`, `String text` (réponse
///   affichée et sauvegardée : tête puis une puce par ligne).
/// - `const String kNoAnswerToken = 'NO_ANSWER'` : réponse réservée du modèle
///   pour « rien d'utile à dire / pas une vraie question pour l'utilisateur ».
///   Règle choisie : une réponse qui COMMENCE par ce jeton est un refus, quoi
///   qui suive (les modèles locaux ajoutent souvent une explication).
/// - `const int kMaxBullets = 3`.
/// - Citations : l'extrait n° i (à partir de 1, dans l'ordre fourni au
///   modèle) se cite `[S<i>]`. Une citation vers un extrait non fourni est
///   jetée : absente des sources ET du texte.
/// - lib/application/services/live_answers/live_question.dart :
///   `AnswerSource({required String documentId, required String title,
///   required String excerpt})` avec égalité de valeur.
/// - Règle « tronquée » choisie : le texte finit sans ponctuation finale
///   (. ! ? … ) » ") ni citation `[S<i>]` après une ponctuation finale.
void main() {
  const DocumentExcerpt contract = DocumentExcerpt(
    documentId: 'doc-contract',
    documentTitle: 'Contrat Acme 2026',
    text: 'Livraison du lot 1 le 12 mars 2026.',
  );
  const DocumentExcerpt pricing = DocumentExcerpt(
    documentId: 'doc-pricing',
    documentTitle: 'Grille tarifaire',
    text: 'Licence : 40 € par utilisateur et par mois.',
  );

  group('refus du modèle', () {
    test('la réponse réservée seule = refus, rien à afficher', () {
      final ParsedAnswer a = parseAnswer(
        kNoAnswerToken,
        const <DocumentExcerpt>[],
      );
      expect(a.declined, isTrue);
      expect(a.text, isEmpty);
      expect(a.sources, isEmpty);
    });

    test('avec des blancs ou un retour à la ligne autour : refus aussi', () {
      expect(
        parseAnswer('  $kNoAnswerToken\n', const <DocumentExcerpt>[]).declined,
        isTrue,
      );
    });

    for (final String raw in <String>[
      '$kNoAnswerToken.',
      "$kNoAnswerToken\nCe n'est pas une question pour vous.",
      '$kNoAnswerToken — rien dans le contexte.',
    ]) {
      test(
        'jeton suivi d\'un texte « ${raw.replaceAll('\n', r'\n')} » : refus, '
        'rien à afficher',
        () {
          final ParsedAnswer a = parseAnswer(raw, const <DocumentExcerpt>[]);
          expect(a.declined, isTrue);
          expect(a.text, isEmpty);
        },
      );
    }

    test('une vraie réponse n\'est pas un refus', () {
      expect(
        parseAnswer('Non, pas avant mars.', const <DocumentExcerpt>[]).declined,
        isFalse,
      );
    });
  });

  group('forme : une tête et au plus trois puces', () {
    test('tête puis puces, marqueurs retirés', () {
      final ParsedAnswer a = parseAnswer(
        'La livraison est prévue le 12 mars.\n'
        '- Lot 1 seulement.\n'
        '• Le lot 2 suit en avril.\n'
        '* Recette d\'une semaine.',
        const <DocumentExcerpt>[],
      );
      expect(a.headline, 'La livraison est prévue le 12 mars.');
      expect(a.bullets, <String>[
        'Lot 1 seulement.',
        'Le lot 2 suit en avril.',
        'Recette d\'une semaine.',
      ]);
    });

    test('cinq puces reçues : trois gardées, les suivantes ni affichées ni '
        'sauvegardées', () {
      final ParsedAnswer a = parseAnswer(
        'Oui.\n- un.\n- deux.\n- trois.\n- QUATRE.\n- CINQ.',
        const <DocumentExcerpt>[],
      );
      expect(a.bullets, hasLength(kMaxBullets));
      expect(a.text, isNot(contains('QUATRE')));
      expect(a.text, isNot(contains('CINQ')));
    });

    test('sans puce : la tête seule', () {
      final ParsedAnswer a = parseAnswer(
        'Oui, dès lundi.',
        const <DocumentExcerpt>[],
      );
      expect(a.headline, 'Oui, dès lundi.');
      expect(a.bullets, isEmpty);
    });
  });

  group('sources : seulement les extraits fournis', () {
    test('une citation valide donne {documentId, titre, extrait}', () {
      final ParsedAnswer a = parseAnswer(
        'Le lot 1 est livré le 12 mars [S1].',
        const <DocumentExcerpt>[contract, pricing],
      );
      expect(a.sources, const <AnswerSource>[
        AnswerSource(
          documentId: 'doc-contract',
          title: 'Contrat Acme 2026',
          excerpt: 'Livraison du lot 1 le 12 mars 2026.',
        ),
      ]);
    });

    test('une citation vers un extrait non fourni est jetée, jamais rendue '
        'comme source', () {
      final ParsedAnswer a = parseAnswer(
        'Le lot 1 est livré le 12 mars [S1] et coûte 3 000 € [S3].',
        const <DocumentExcerpt>[contract, pricing],
      );
      expect(a.sources.map((AnswerSource s) => s.documentId), <String>[
        'doc-contract',
      ]);
      expect(a.text, isNot(contains('[S3]')));
    });

    test('citation sans aucun extrait fourni : aucune source', () {
      final ParsedAnswer a = parseAnswer(
        'Le lot 1 est livré le 12 mars [S1].',
        const <DocumentExcerpt>[],
      );
      expect(a.sources, isEmpty);
      expect(a.text, isNot(contains('[S1]')));
    });

    test('la même source citée deux fois n\'apparaît qu\'une fois', () {
      final ParsedAnswer a = parseAnswer(
        'Livré le 12 mars [S2].\n- Prix par mois [S2].\n- Prix par an [S1].',
        const <DocumentExcerpt>[contract, pricing],
      );
      expect(a.sources.map((AnswerSource s) => s.documentId), <String>[
        'doc-pricing',
        'doc-contract',
      ]);
    });

    test('extraits fournis mais rien de cité : aucune source', () {
      expect(
        parseAnswer('Oui.', const <DocumentExcerpt>[contract]).sources,
        isEmpty,
      );
    });
  });

  group(
    'réponse tronquée (fin du flux sans erreur, au milieu d\'une phrase)',
    () {
      test(
        'coupée au milieu d\'un mot : montrée telle quelle, marquée tronquée',
        () {
          final ParsedAnswer a = parseAnswer(
            'La livraison est prévue pour le lot 1 au début du mo',
            const <DocumentExcerpt>[],
          );
          expect(a.truncated, isTrue);
          expect(
            a.text,
            'La livraison est prévue pour le lot 1 au début du mo',
          );
        },
      );

      test('phrase finie : pas tronquée', () {
        expect(
          parseAnswer(
            'La livraison est prévue le 12 mars.',
            const <DocumentExcerpt>[],
          ).truncated,
          isFalse,
        );
      });

      test('phrase finie suivie d\'une citation : pas tronquée', () {
        expect(
          parseAnswer('Livré le 12 mars. [S1]', const <DocumentExcerpt>[
            contract,
          ]).truncated,
          isFalse,
        );
      });
    },
  );

  group('refus habillé (markdown, guillemets, ponctuation)', () {
    for (final String raw in <String>[
      '**$kNoAnswerToken**',
      '`$kNoAnswerToken`',
      '*$kNoAnswerToken*',
      '"$kNoAnswerToken"',
      '« $kNoAnswerToken »',
      '$kNoAnswerToken.',
      '**$kNoAnswerToken**.',
      '> $kNoAnswerToken',
    ]) {
      test('« $raw » : refus, jamais affiché', () {
        final ParsedAnswer a = parseAnswer(raw, const <DocumentExcerpt>[]);
        expect(a.declined, isTrue);
        expect(a.text, isEmpty);
      });
    }

    test('le jeton cité au milieu d\'une vraie réponse n\'est pas un refus', () {
      final ParsedAnswer a = parseAnswer(
        'Oui, livré le 12 mars.\n- Le code NO_ANSWER ne concerne que le modèle.',
        const <DocumentExcerpt>[],
      );
      expect(a.declined, isFalse);
    });
  });

  group('puces sans point final (règle choisie : sans signal de fin de '
      'longueur du fournisseur, une dernière puce est coupée seulement si '
      'elle finit sur un signe de suite , ; : - – ( ou sur un mot outil '
      'de/du/des/le/la/les/un/une/et/ou/à/au/aux/pour/par/avec/en/sur/'
      'the/a/an/of/to/and/or/for/with/in/on/at, ou si elle est vide)', () {
    for (final String raw in <String>[
      'Oui.\n- Lot 1 le 12 mars\n- Lot 2 en avril',
      'Yes.\n- Batch 1 on March 12\n- Batch 2 in April',
      'Oui.\n- Recette d\'une semaine\n- Formation incluse',
    ]) {
      test('« ${raw.replaceAll('\n', r'\n')} » : complète, pas tronquée', () {
        expect(parseAnswer(raw, const <DocumentExcerpt>[]).truncated, isFalse);
      });
    }

    for (final String raw in <String>[
      'Oui.\n- Lot 1 le 12 mars\n- Lot 2 prévu pour le',
      'Oui.\n- Lot 1 le 12 mars\n- Lot 2 :',
      'Oui.\n- Lot 1 le 12 mars,',
      'Oui.\n- Lot 1 le 12 mars\n-',
      'Yes.\n- Batch 1 on March 12\n- Batch 2 planned for the',
      'Oui.\n- Prix (hors',
    ]) {
      test('« ${raw.replaceAll('\n', r'\n')} » : tronquée', () {
        expect(parseAnswer(raw, const <DocumentExcerpt>[]).truncated, isTrue);
      });
    }

    test('tête seule sans ponctuation finale : tronquée, comme avant', () {
      expect(
        parseAnswer(
          'La livraison est prévue pour',
          const <DocumentExcerpt>[],
        ).truncated,
        isTrue,
      );
    });
  });
}
