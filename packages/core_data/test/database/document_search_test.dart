import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/document.dao.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'v1_database.dart';

/// Documents sources decoupes en morceaux, avec recherche plein texte
/// (FTS5) : une question detectee en reunion doit retrouver les morceaux
/// les plus pertinents, avec le titre de leur document.
void main() {
  late AppDatabase db;
  late DocumentDao dao;

  Future<void> addDocument(String id, String title, List<String> chunks) async {
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            title: title,
            path: '/Users/me/Documents/$id.md',
            addedAt: '2026-11-22T10:00:00.000',
          ),
        );
    for (int i = 0; i < chunks.length; i++) {
      await db
          .into(db.documentChunks)
          .insert(
            DocumentChunksCompanion.insert(
              id: '$id-$i',
              documentId: id,
              position: i,
              content: chunks[i],
            ),
          );
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DocumentDao(db);
  });
  tearDown(() => db.close());

  test(
    'un morceau qui contient les termes passe devant un morceau sans rapport',
    () async {
      await addDocument('rh', 'Plan de recrutement', <String>[
        'Le recrutement de deux développeurs commence en janvier.',
      ]);
      await addDocument('budget', 'Budget 2027', <String>[
        'Le budget global sera présenté au comité.',
        'Le budget marketing 2027 est fixé à 40 000 euros.',
      ]);

      final List<DocumentSearchResult> results = await dao.search(
        'budget marketing',
      );

      expect(results, isNotEmpty);
      expect(
        results.first.content,
        'Le budget marketing 2027 est fixé à 40 000 euros.',
      );
      final int unrelated = results.indexWhere(
        (DocumentSearchResult r) => r.documentId == 'rh',
      );
      expect(unrelated, anyOf(-1, greaterThan(0)));
    },
  );

  test('chaque résultat porte le titre de son document', () async {
    await addDocument('budget', 'Budget 2027', <String>[
      'Le budget marketing 2027 est fixé à 40 000 euros.',
    ]);

    final DocumentSearchResult hit = (await dao.search('marketing')).single;

    expect(hit.documentId, 'budget');
    expect(hit.documentTitle, 'Budget 2027');
    expect(hit.content, 'Le budget marketing 2027 est fixé à 40 000 euros.');
  });

  test(
    'une question en langage naturel trouve le morceau même si tous ses mots '
    'n’y figurent pas',
    () async {
      // Les questions detectees contiennent des mots absents des documents
      // ("quel", "est", "notre") : la recherche cherche le meilleur morceau,
      // elle n'exige pas que tous les mots soient presents.
      await addDocument('budget', 'Budget 2027', <String>[
        'Le budget marketing 2027 est fixé à 40 000 euros.',
      ]);

      final List<DocumentSearchResult> results = await dao.search(
        'Quel est notre budget marketing pour l’an prochain',
      );

      expect(
        results.map((DocumentSearchResult r) => r.documentId),
        contains('budget'),
      );
    },
  );

  test(
    'la recherche ignore la casse, y compris sur les capitales accentuées',
    () async {
      await addDocument('cr', 'Compte rendu', <String>[
        'Prochaine réunion avec le BUREAU le 3 décembre.',
      ]);

      expect(await dao.search('RÉUNION'), hasLength(1));
      expect(await dao.search('bureau'), hasLength(1));
    },
  );

  test(
    'une requête vide ou faite d’espaces ne renvoie rien, sans erreur',
    () async {
      await addDocument('budget', 'Budget 2027', <String>['Le budget 2027.']);

      expect(await dao.search(''), isEmpty);
      expect(await dao.search('   \n'), isEmpty);
    },
  );

  test('une question avec apostrophes, guillemets et ponctuation ne lève pas '
      'd’erreur et trouve le morceau', () async {
    // Syntaxe FTS5 : ' " ( ) * - : ? sont des caracteres speciaux.
    await addDocument('budget', 'Budget 2027', <String>[
      'Le budget de l\'équipe produit a été validé.',
    ]);

    final List<DocumentSearchResult> results = await dao.search(
      'L\'équipe "produit" a-t-elle validé le budget ? (2027) * OR: NEAR',
    );

    expect(
      results.map((DocumentSearchResult r) => r.documentId),
      contains('budget'),
    );
  });

  test('supprimer un document supprime ses morceaux et les retire de la '
      'recherche', () async {
    await addDocument('budget', 'Budget 2027', <String>[
      'Le budget marketing 2027 est fixé à 40 000 euros.',
      'Le budget formation est stable.',
    ]);
    await addDocument('rh', 'Plan de recrutement', <String>[
      'Le budget recrutement double.',
    ]);

    await (db.delete(
      db.documents,
    )..where(($DocumentsTable t) => t.id.equals('budget'))).go();

    final List<DocumentChunk> chunks = await db.select(db.documentChunks).get();
    expect(chunks.map((DocumentChunk c) => c.documentId), <String>['rh']);
    final List<DocumentSearchResult> results = await dao.search('budget');
    expect(results.map((DocumentSearchResult r) => r.documentId), <String>[
      'rh',
    ]);
  });

  test('après la migration 1 -> 2, la recherche fonctionne', () async {
    await db.close();
    db = AppDatabase(v1DatabaseWithData());
    dao = DocumentDao(db);

    await addDocument('budget', 'Budget 2027', <String>[
      'Le budget marketing 2027 est fixé à 40 000 euros.',
    ]);

    expect((await dao.search('marketing')).single.documentTitle, 'Budget 2027');
  });
}
