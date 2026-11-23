import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

/// Revue de PR #23 : la règle du refus en prose ne doit pas cacher une
/// réponse sourcée, et le nettoyage des citations ne doit pas toucher aux
/// parenthèses du texte. Les 12 refus enregistrés restent fixés par
/// recorded_outputs_test.dart (inchangé).
void main() {
  const List<DocumentExcerpt> excerpts = <DocumentExcerpt>[
    DocumentExcerpt(
      documentId: 'doc-gite',
      documentTitle: 'Informations du gîte',
      text: 'Le petit-déjeuner n\'est pas fourni. Arrivée possible dès 10 h.',
    ),
    DocumentExcerpt(
      documentId: 'doc-offre',
      documentTitle: 'Offre de base',
      text: 'Le support n\'est pas inclus dans l\'offre de base.',
    ),
  ];

  ParsedAnswer parse(String raw) => parseAnswer(raw, excerpts);

  group('1. réponses sourcées qui contiennent une négation : réponses', () {
    for (final String raw in <String>[
      'Arrivée au gîte\n'
          '- L\'arrivée est possible dès 10 h [S1].\n'
          '- L\'heure exacte du dîner n\'est pas précisée.',
      'Arrival at the lodge\n'
          '- Arrival is possible from 10 am [S1].\n'
          '- The exact dinner time is not specified.',
      'Arrivée au gîte :\n'
          '- L\'arrivée est possible dès 10 h [S1].\n'
          '- L\'heure du dîner non précisée.',
    ]) {
      test('titre, puce sourcée avec du contenu, puce « non précisé » : '
          'réponse (${raw.split('\n').first})', () {
        final ParsedAnswer a = parse(raw);
        expect(a.declined, isFalse);
        expect(a.text, contains('10'));
        expect(a.sources.map((AnswerSource s) => s.documentId), <String>[
          'doc-gite',
        ]);
      });
    }

    for (final String raw in <String>[
      'Breakfast is not provided. [S1]',
      'Le support n\'est pas indiqué comme inclus dans l\'offre de base. [S2]',
      'Aucune information confidentielle ne doit sortir. [S1]',
    ]) {
      test('état du monde sourcé « $raw » : réponse', () {
        final ParsedAnswer a = parse(raw);
        expect(a.declined, isFalse);
        expect(a.headline, isNotEmpty);
        expect(a.sources, isNotEmpty);
      });
    }

    test('tête qui répond puis « The exact date is not specified. » : '
        'réponse', () {
      final ParsedAnswer a = parse(
        'The meeting with the vendor takes place after the pilot [S1]. '
        'The exact date is not specified.',
      );
      expect(a.declined, isFalse);
      expect(a.text, contains('after the pilot'));
    });
  });

  group('2. parenthèses du texte : gardées', () {
    test('« (14:30) » dans une réponse sur une heure : gardé tel quel', () {
      final ParsedAnswer a = parse(
        'Le point avec le prestataire est jeudi après-midi (14:30) [S1].',
      );
      expect(a.text, contains('(14:30)'));
      expect(a.sources.map((AnswerSource s) => s.documentId), <String>[
        'doc-gite',
      ]);
    });

    test('« (S2) » pour un semestre : du texte, pas une citation', () {
      final ParsedAnswer a = parse(
        'Le nouveau module arrive au second semestre (S2) 2027.',
      );
      expect(a.text, contains('(S2)'));
      expect(a.sources, isEmpty);
    });

    test('« [S2] » entre crochets reste une citation', () {
      final ParsedAnswer a = parse(
        'Le support n\'est pas inclus dans l\'offre de base [S2].',
      );
      expect(a.sources.map((AnswerSource s) => s.documentId), <String>[
        'doc-offre',
      ]);
    });
  });
}
