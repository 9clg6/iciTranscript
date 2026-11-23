import 'package:core_data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';

import '../../../helpers/document_fakes.dart';

/// Recherche pour ancrer une réponse (besoin A4) : une question en langage
/// naturel → les meilleurs extraits, avec l'id et le titre du document.
///
/// API supposée (lib/application/services/documents/document_library.dart) :
/// - `DocumentLibrary.search(String question, {int limit = 5})` rend un
///   `Future<List<DocumentExcerpt>>`, du plus pertinent au moins pertinent.
/// - `DocumentExcerpt {documentId, documentTitle, text}`.
/// - `kMaxExcerptChars = 400` : longueur maximale d'un extrait, points de
///   suspension compris ; un morceau plus long est coupé AUTOUR du passage
///   trouvé.
/// - Mots vides français retirés de la question ; au minimum : le, la, les,
///   l', de, des, du, d', un, une, et, est, que, qu', quel, quelle, quels,
///   quelles, ce, c', il, elle, on, nous, vous, à, au, aux, en, pour, sur,
///   dans, avec, ne, pas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentLibrary library;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = DocumentLibrary(db);
  });
  tearDown(() => db.close());

  Future<String> add(String name, String text) async =>
      (await library.importFile(writeFile(tempFolder(), name, text))).id;

  test('chaque extrait porte l\'id et le titre de son document', () async {
    final String id = await add(
      'Budget 2027.md',
      'Le budget marketing 2027 est fixé à 40 000 euros.',
    );

    final DocumentExcerpt hit = (await library.search(
      'Quel est le budget marketing ?',
    )).single;

    expect(hit.documentId, id);
    expect(hit.documentTitle, 'Budget 2027');
    expect(hit.text, 'Le budget marketing 2027 est fixé à 40 000 euros.');
  });

  test('les mots vides de la question ne font pas remonter un document qui '
      'ne contient qu\'eux', () async {
    await add('equipe.md', 'Le budget de l\'équipe produit est validé.');
    await add(
      'bavard.md',
      'Il est là, et le reste est à faire, de toute façon, que ce soit '
          'pour nous ou pour vous, dans le calme et avec le sourire.',
    );

    final List<DocumentExcerpt> hits = await library.search(
      'Quel est le budget de l\'équipe ?',
    );

    expect(hits.map((DocumentExcerpt e) => e.documentTitle), <String>[
      'equipe',
    ]);
  });

  for (final String question in <String>[
    'Qu\'est-ce que c\'est ?',
    'Est-ce que le, la, les, de ?',
    '',
    '   \n',
    '?!… « » — ()',
  ]) {
    test('question sans mot utile « $question » : rien, sans erreur', () async {
      await add('bavard.md', 'Qu\'est-ce que c\'est ? Est-ce le la les de.');

      expect(await library.search(question), isEmpty);
    });
  }

  test('ponctuation et syntaxe FTS dans la question : aucune erreur, le '
      'document est trouvé', () async {
    await add('equipe.md', 'Le budget de l\'équipe produit a été validé.');

    final List<DocumentExcerpt> hits = await library.search(
      'L\'équipe "produit" a-t-elle validé le budget ? (2027) * OR: NEAR -x',
    );

    expect(
      hits.map((DocumentExcerpt e) => e.documentTitle),
      contains('equipe'),
    );
  });

  test('accents et casse ignorés comme le tokenizer existant', () async {
    await add('cr.md', 'Prochaine réunion avec l\'équipe le 3 décembre.');

    expect(await library.search('reunion'), hasLength(1));
    expect(await library.search('EQUIPE'), hasLength(1));
    expect(await library.search('Décembre'), hasLength(1));
  });

  test('ordre de pertinence : le morceau qui contient tous les termes passe '
      'devant celui qui n\'en contient qu\'un', () async {
    await add('global.md', 'Le budget global sera présenté au comité.');
    await add('marketing.md', 'Le budget marketing 2027 : 40 000 euros.');

    final List<DocumentExcerpt> hits = await library.search(
      'Quel budget pour le marketing ?',
    );

    expect(hits.first.documentTitle, 'marketing');
  });

  test('résultats limités : limit respecté, 5 par défaut', () async {
    for (int i = 0; i < 8; i++) {
      await add('doc$i.md', 'Le budget numéro $i est validé.');
    }

    expect(await library.search('budget', limit: 3), hasLength(3));
    expect(await library.search('budget'), hasLength(5));
  });

  test('un extrait court est rendu entier', () async {
    await add('court.md', 'Le budget est validé.');

    expect(
      (await library.search('budget')).single.text,
      'Le budget est validé.',
    );
  });

  test(
    'un morceau long est coupé autour du passage trouvé, dans la borne',
    () async {
      final String filler = List<String>.filled(90, 'remplissage').join(' ');
      await add(
        'long.md',
        '$filler. La décision finale revient à l\'équipe produit.',
      );

      final DocumentExcerpt hit = (await library.search('equipe')).single;

      expect(kMaxExcerptChars, 400);
      expect(hit.text.length, lessThanOrEqualTo(kMaxExcerptChars));
      expect(hit.text, contains('équipe'));
    },
  );

  test(
    'passage trouvé au début d\'un morceau long : le début est gardé',
    () async {
      final String filler = List<String>.filled(90, 'remplissage').join(' ');
      await add('debut.md', 'Ordre du jour : le budget. $filler.');

      final DocumentExcerpt hit = (await library.search('budget')).single;

      expect(hit.text.length, lessThanOrEqualTo(kMaxExcerptChars));
      expect(hit.text, startsWith('Ordre du jour : le budget.'));
    },
  );
}
