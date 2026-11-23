import 'dart:io';

import 'package:clock/clock.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/services/document_chunker.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';

import '../../../helpers/document_fakes.dart';

/// Bibliothèque de documents sources (besoins A1 à A3) : l'utilisateur ajoute
/// des fichiers .txt, .md ou .pdf pour que les réponses pendant ses réunions
/// s'appuient dessus.
///
/// API supposée (lib/application/services/documents/document_library.dart) :
/// - `DocumentLibrary(AppDatabase db, {int maxTextChars = kMaxDocumentTextChars})`
/// - `Future<LibraryDocument> importFile(String path)` : lit le fichier une
///   fois (PDF : canal `com.icitranscript/document_text`, méthode
///   `extractText {path}` → String), découpe avec `chunkDocument`, range le
///   document et ses morceaux dans une seule transaction ; même chemin =
///   remplace la version précédente. Refus = sous-type de
///   `DocumentImportException` (champ `path`) :
///   `UnsupportedDocumentTypeException`, `EmptyDocumentException`,
///   `DocumentTooLargeException`, `UnreadableDocumentException`.
/// - `Future<List<LibraryDocument>> list()` : le plus récent d'abord.
/// - `Future<void> rename(String id, String title)`, `Future<void> delete(String id)`.
/// - `LibraryDocument {id, title, type (DocumentType.txt|md|pdf), addedAt
///   (DateTime, via package:clock), excerptCount, path}` ; titre par défaut =
///   nom du fichier sans extension ; type tiré de l'extension (sans casse).
/// - `kMaxDocumentTextChars = 5 * 1024 * 1024` : borne en CARACTÈRES du texte
///   extrait (pas en octets du fichier).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentLibrary library;
  late Directory dir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = DocumentLibrary(db);
    dir = tempFolder();
  });
  tearDown(() => db.close());

  Future<int> count(String table) async {
    final QueryRow row = await db
        .customSelect('SELECT count(*) AS n FROM $table')
        .getSingle();
    return row.read<int>('n');
  }

  Future<List<String>> storedChunks(String documentId) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT content FROM document_chunks WHERE document_id = ? '
          'ORDER BY position',
          variables: <Variable<Object>>[Variable<String>(documentId)],
        )
        .get();
    return rows.map((QueryRow r) => r.read<String>('content')).toList();
  }

  Future<List<int>> storedPositions(String documentId) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT position FROM document_chunks WHERE document_id = ? '
          'ORDER BY position',
          variables: <Variable<Object>>[Variable<String>(documentId)],
        )
        .get();
    return rows.map((QueryRow r) => r.read<int>('position')).toList();
  }

  Future<void> expectNothingStored() async {
    expect(await count('documents'), 0);
    expect(await count('document_chunks'), 0);
    expect(await count('document_chunks_fts'), 0);
  }

  /// Texte de [n] paragraphes de 1000 caractères : `chunkDocument` en fait
  /// [n] morceaux (deux ne tiennent pas dans 1200).
  String paragraphs(int n, String word) => List<String>.generate(
    n,
    (int i) => List<String>.filled(100, '$word$i'.padRight(9)).join(' '),
  ).join('\n\n');

  group('ajout depuis un chemin', () {
    test('un .md est découpé avec chunkDocument et rangé dans l\'ordre', () async {
      final String text = paragraphs(4, 'budget');
      final String path = writeFile(dir, 'Plan de recrutement.md', text);

      final LibraryDocument doc = await withClock(
        Clock.fixed(DateTime(2026, 11, 22, 10, 30)),
        () => library.importFile(path),
      );

      expect(doc.title, 'Plan de recrutement');
      expect(doc.type, DocumentType.md);
      expect(doc.addedAt, DateTime(2026, 11, 22, 10, 30));
      expect(doc.excerptCount, chunkDocument(text).length);
      expect(await storedChunks(doc.id), chunkDocument(text));
      expect(
        await storedPositions(doc.id),
        List<int>.generate(chunkDocument(text).length, (int i) => i),
      );
      expect(await count('document_chunks_fts'), chunkDocument(text).length);
    });

    test('un .txt est accepté', () async {
      final String path = writeFile(dir, 'notes.txt', 'Le budget est validé.');

      final LibraryDocument doc = await library.importFile(path);

      expect(doc.type, DocumentType.txt);
      expect(doc.title, 'notes');
      expect(await storedChunks(doc.id), <String>['Le budget est validé.']);
    });

    test('l\'extension est reconnue sans tenir compte de la casse', () async {
      final String path = writeFile(dir, 'NOTES.MD', 'Ordre du jour.');

      final LibraryDocument doc = await library.importFile(path);

      expect(doc.type, DocumentType.md);
      expect(doc.title, 'NOTES');
    });

    for (final String name in <String>[
      'contrat.docx',
      'photo.png',
      'sans_extension',
      'archive.md.zip',
    ]) {
      test('$name : type refusé avec un message explicite, rien rangé', () async {
        final String path = writeFile(dir, name, 'Du texte lisible.');

        await expectLater(
          library.importFile(path),
          throwsA(
            isA<UnsupportedDocumentTypeException>().having(
              (UnsupportedDocumentTypeException e) => e.path,
              'path',
              path,
            ),
          ),
        );
        await expectNothingStored();
      });
    }

    for (final MapEntry<String, String> empty in <String, String>{
      'vide': '',
      'fait d\'espaces': '  \n\t \n\n   ',
    }.entries) {
      test('document ${empty.key} : refusé, rien rangé', () async {
        final String path = writeFile(dir, 'vide.txt', empty.value);

        await expectLater(
          library.importFile(path),
          throwsA(isA<EmptyDocumentException>()),
        );
        await expectNothingStored();
      });
    }

    test('fichier introuvable : refusé (illisible), rien rangé', () async {
      await expectLater(
        library.importFile('${dir.path}/absent.md'),
        throwsA(isA<UnreadableDocumentException>()),
      );
      await expectNothingStored();
    });

    test('octets qui ne sont pas de l\'UTF-8 : jamais une autre erreur qu\'un '
        'refus de la bibliothèque', () async {
      final File file = File('${dir.path}/latin1.txt')
        ..writeAsBytesSync(<int>[0x43, 0x61, 0x66, 0xe9, 0xff, 0xfe, 0x2e]);

      try {
        await library.importFile(file.path);
      } on DocumentImportException {
        await expectNothingStored();
      }
    });
  });

  group('taille bornée', () {
    test('la borne par défaut est de 5 Mo de texte', () {
      expect(kMaxDocumentTextChars, 5 * 1024 * 1024);
    });

    test('au-delà de la borne : refusé avec un message, rien rangé', () async {
      final DocumentLibrary small = DocumentLibrary(db, maxTextChars: 100);
      final String path = writeFile(dir, 'long.txt', 'a' * 101);

      await expectLater(
        small.importFile(path),
        throwsA(isA<DocumentTooLargeException>()),
      );
      await expectNothingStored();
    });

    test('à la borne exacte : accepté', () async {
      final DocumentLibrary small = DocumentLibrary(db, maxTextChars: 100);
      final String path = writeFile(dir, 'juste.txt', 'a' * 100);

      final LibraryDocument doc = await small.importFile(path);

      expect(doc.excerptCount, 1);
    });

    test('un fichier de plus de 5 Mo de texte est refusé avec la borne par '
        'défaut', () async {
      final String path = writeFile(
        dir,
        'enorme.txt',
        'a' * (5 * 1024 * 1024 + 1),
      );

      await expectLater(
        library.importFile(path),
        throwsA(isA<DocumentTooLargeException>()),
      );
      await expectNothingStored();
    });
  });

  group('une seule transaction', () {
    /// Fait échouer l'insertion du 3e morceau (disque plein, base verrouillée).
    Future<void> failOnThirdChunk() => db.customStatement(
      'CREATE TEMP TRIGGER fail_third_chunk BEFORE INSERT ON document_chunks '
      "WHEN new.position = 2 BEGIN SELECT RAISE(ABORT, 'disque plein'); END",
    );

    test('un échec au milieu de l\'enregistrement ne laisse rien', () async {
      final String path = writeFile(dir, 'gros.md', paragraphs(5, 'budget'));
      await failOnThirdChunk();

      await expectLater(library.importFile(path), throwsA(anything));

      await expectNothingStored();
      expect(await library.list(), isEmpty);
      expect(await library.search('budget0'), isEmpty);
    });

    test('un ré-import qui échoue au milieu garde la version précédente '
        'entière et cherchable', () async {
      final String path = writeFile(dir, 'plan.md', 'Ancienne version du plan.');
      final LibraryDocument first = await library.importFile(path);
      File(path).writeAsStringSync(paragraphs(5, 'nouveau'));
      await failOnThirdChunk();

      await expectLater(library.importFile(path), throwsA(anything));

      final List<LibraryDocument> docs = await library.list();
      expect(docs.map((LibraryDocument d) => d.id), <String>[first.id]);
      expect(await storedChunks(first.id), <String>['Ancienne version du plan.']);
      expect(await library.search('ancienne version'), hasLength(1));
      expect(await library.search('nouveau0'), isEmpty);
    });
  });

  group('lu une fois à l\'ajout', () {
    test('fichier supprimé ensuite : le document reste listé et cherchable', () async {
      final String path = writeFile(dir, 'budget.md', 'Le budget marketing 2027.');
      await library.importFile(path);

      File(path).deleteSync();

      expect(await library.list(), hasLength(1));
      final List<DocumentExcerpt> hits = await library.search('marketing');
      expect(hits.single.text, 'Le budget marketing 2027.');
    });

    test('fichier déplacé ensuite : le document reste cherchable', () async {
      final String path = writeFile(dir, 'budget.md', 'Le budget marketing 2027.');
      await library.importFile(path);

      File(path).renameSync('${dir.path}/ailleurs.md');

      expect(await library.search('marketing'), hasLength(1));
    });

    test('ré-importer le même chemin remplace la version précédente : un seul '
        'document, pas de morceau en double, index cohérent', () async {
      final String path = writeFile(dir, 'plan.md', 'Version alpha du plan.');
      await library.importFile(path);
      final String v2 = paragraphs(3, 'beta');
      File(path).writeAsStringSync(v2);

      final LibraryDocument second = await library.importFile(path);

      final List<LibraryDocument> docs = await library.list();
      expect(docs, hasLength(1));
      expect(docs.single.excerptCount, chunkDocument(v2).length);
      expect(await count('document_chunks'), chunkDocument(v2).length);
      expect(await count('document_chunks_fts'), chunkDocument(v2).length);
      expect(await storedChunks(second.id), chunkDocument(v2));
      expect(await library.search('alpha'), isEmpty);
      expect(await library.search('beta0'), hasLength(1));
    });

    test('deux fichiers de même nom dans deux dossiers sont deux documents', () async {
      final Directory other = Directory('${dir.path}/autre')..createSync();
      await library.importFile(writeFile(dir, 'plan.md', 'Plan A.'));
      await library.importFile(writeFile(other, 'plan.md', 'Plan B.'));

      expect(await library.list(), hasLength(2));
    });
  });

  group('PDF par le canal com.icitranscript/document_text', () {
    test('extractText {path} : le texte rendu est découpé et rangé', () async {
      final String path = writeFile(dir, 'Rapport annuel.pdf', '%PDF-1.4');
      final List<MethodCall> calls = mockPdfChannel(
        (MethodCall call) async => 'Le chiffre d\'affaires 2026 progresse.',
      );

      final LibraryDocument doc = await library.importFile(path);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'extractText');
      expect(calls.single.arguments, <String, Object?>{'path': path});
      expect(doc.type, DocumentType.pdf);
      expect(doc.title, 'Rapport annuel');
      expect(await library.search('affaires'), hasLength(1));
    });

    test('.PDF en capitales passe aussi par le canal', () async {
      final String path = writeFile(dir, 'SCAN.PDF', '%PDF-1.4');
      final List<MethodCall> calls = mockPdfChannel(
        (MethodCall call) async => 'Texte extrait.',
      );

      final LibraryDocument doc = await library.importFile(path);

      expect(calls, hasLength(1));
      expect(doc.type, DocumentType.pdf);
    });

    test('PDF sans texte (scan) : refusé comme document vide', () async {
      final String path = writeFile(dir, 'scan.pdf', '%PDF-1.4');
      mockPdfChannel((MethodCall call) async => '   ');

      await expectLater(
        library.importFile(path),
        throwsA(isA<EmptyDocumentException>()),
      );
      await expectNothingStored();
    });

    test('PDF protégé ou abîmé (PlatformException) : refusé comme illisible', () async {
      final String path = writeFile(dir, 'protege.pdf', '%PDF-1.4');
      mockPdfChannel(
        (MethodCall call) async =>
            throw PlatformException(code: 'unreadable', message: 'locked'),
      );

      await expectLater(
        library.importFile(path),
        throwsA(isA<UnreadableDocumentException>()),
      );
      await expectNothingStored();
    });

    test('canal absent (MissingPluginException) : refusé comme illisible', () async {
      final String path = writeFile(dir, 'rapport.pdf', '%PDF-1.4');

      await expectLater(
        library.importFile(path),
        throwsA(isA<UnreadableDocumentException>()),
      );
      await expectNothingStored();
    });

    test('un PDF au texte trop long est refusé', () async {
      final DocumentLibrary small = DocumentLibrary(db, maxTextChars: 50);
      final String path = writeFile(dir, 'long.pdf', '%PDF');
      mockPdfChannel((MethodCall call) async => 'b' * 51);

      await expectLater(
        small.importFile(path),
        throwsA(isA<DocumentTooLargeException>()),
      );
      await expectNothingStored();
    });
  });

  group('liste, renommage, suppression', () {
    test('la liste donne titre, type, date d\'ajout et nombre d\'extraits, le '
        'plus récent d\'abord', () async {
      await withClock(
        Clock.fixed(DateTime(2026, 11, 20, 9)),
        () => library.importFile(writeFile(dir, 'ancien.txt', 'Ancien.')),
      );
      final String text = paragraphs(3, 'recent');
      await withClock(
        Clock.fixed(DateTime(2026, 11, 21, 9)),
        () => library.importFile(writeFile(dir, 'récent.md', text)),
      );

      final List<LibraryDocument> docs = await library.list();

      expect(docs.map((LibraryDocument d) => d.title), <String>[
        'récent',
        'ancien',
      ]);
      expect(docs.first.type, DocumentType.md);
      expect(docs.first.addedAt, DateTime(2026, 11, 21, 9));
      expect(docs.first.excerptCount, chunkDocument(text).length);
      expect(docs.last.type, DocumentType.txt);
      expect(docs.last.excerptCount, 1);
    });

    test('bibliothèque vide : liste vide, sans erreur', () async {
      expect(await library.list(), isEmpty);
    });

    test('renommer change le titre de la liste et des extraits trouvés', () async {
      final LibraryDocument doc = await library.importFile(
        writeFile(dir, 'b27.md', 'Le budget marketing 2027.'),
      );

      await library.rename(doc.id, '  Budget 2027  ');

      expect((await library.list()).single.title, 'Budget 2027');
      expect(
        (await library.search('marketing')).single.documentTitle,
        'Budget 2027',
      );
    });

    test('renommer avec un titre vide garde l\'ancien titre', () async {
      final LibraryDocument doc = await library.importFile(
        writeFile(dir, 'plan.md', 'Plan.'),
      );

      await library.rename(doc.id, '   ');

      expect((await library.list()).single.title, 'plan');
    });

    test('supprimer retire le document, ses morceaux et ses résultats de '
        'recherche, sans toucher aux autres', () async {
      final LibraryDocument budget = await library.importFile(
        writeFile(dir, 'budget.md', paragraphs(2, 'budget')),
      );
      await library.importFile(
        writeFile(dir, 'rh.md', 'Le budget recrutement double.'),
      );

      await library.delete(budget.id);

      expect((await library.list()).map((LibraryDocument d) => d.title),
          <String>['rh']);
      expect(await storedChunks(budget.id), isEmpty);
      expect(await count('document_chunks_fts'), 1);
      expect(await library.search('budget0'), isEmpty);
      expect(
        (await library.search('budget')).map((DocumentExcerpt e) => e.documentTitle),
        <String>['rh'],
      );
    });
  });
}
