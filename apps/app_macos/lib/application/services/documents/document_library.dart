import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/document.dao.dart';
import 'package:core_domain/domain/services/document_chunker.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

/// Borne du texte extrait d'un document, en caractères (5 Mo de texte).
const int kMaxDocumentTextChars = 5 * 1024 * 1024;

/// Longueur maximale d'un extrait rendu par [DocumentLibrary.search],
/// points de suspension compris.
const int kMaxExcerptChars = 400;

/// Formats acceptés, d'après l'extension du fichier.
enum DocumentType {
  /// Texte brut.
  txt,

  /// Markdown.
  md,

  /// PDF (texte extrait par PDFKit).
  pdf,
}

/// Document de la bibliothèque.
class LibraryDocument {
  /// Crée un [LibraryDocument].
  const LibraryDocument({
    required this.id,
    required this.title,
    required this.type,
    required this.addedAt,
    required this.excerptCount,
    required this.path,
  });

  /// Identifiant.
  final String id;

  /// Titre affiché (nom du fichier sans extension par défaut).
  final String title;

  /// Format, tiré de l'extension.
  final DocumentType type;

  /// Date du dernier ajout.
  final DateTime addedAt;

  /// Nombre de morceaux indexés.
  final int excerptCount;

  /// Chemin du fichier au moment de l'ajout.
  final String path;
}

/// Extrait trouvé pour une question.
class DocumentExcerpt {
  /// Crée un [DocumentExcerpt].
  const DocumentExcerpt({
    required this.documentId,
    required this.documentTitle,
    required this.text,
  });

  /// Document d'origine.
  final String documentId;

  /// Titre du document d'origine.
  final String documentTitle;

  /// Passage, au plus [kMaxExcerptChars] caractères.
  final String text;
}

/// Refus d'un fichier à l'ajout.
sealed class DocumentImportException implements Exception {
  const DocumentImportException(this.path);

  /// Fichier refusé.
  final String path;

  @override
  String toString() => '$runtimeType: $path';
}

/// Extension autre que .txt, .md ou .pdf.
final class UnsupportedDocumentTypeException extends DocumentImportException {
  /// Crée l'exception.
  const UnsupportedDocumentTypeException(super.path);
}

/// Aucun texte à indexer.
final class EmptyDocumentException extends DocumentImportException {
  /// Crée l'exception.
  const EmptyDocumentException(super.path);
}

/// Texte plus long que la borne.
final class DocumentTooLargeException extends DocumentImportException {
  /// Crée l'exception.
  const DocumentTooLargeException(super.path);
}

/// Fichier absent, protégé, abîmé ou dans un encodage inconnu.
final class UnreadableDocumentException extends DocumentImportException {
  /// Crée l'exception.
  const UnreadableDocumentException(super.path);
}

const MethodChannel _pdfChannel = MethodChannel(
  'com.icitranscript/document_text',
);

/// Bibliothèque de documents sources : ajout (lu une fois), liste,
/// renommage, suppression et recherche pour ancrer une réponse.
class DocumentLibrary {
  /// Crée la bibliothèque sur [db].
  DocumentLibrary(this._db, {this.maxTextChars = kMaxDocumentTextChars});

  final AppDatabase _db;

  /// Borne du texte extrait, en caractères.
  final int maxTextChars;

  /// Lit [path], le découpe et le range ; même chemin = remplace la version
  /// précédente (id et titre gardés). Une seule transaction.
  Future<LibraryDocument> importFile(String path) async {
    final DocumentType type = _typeOf(path);
    final String text = await _read(path, type);
    if (text.length > maxTextChars) throw DocumentTooLargeException(path);
    if (text.trim().isEmpty) throw EmptyDocumentException(path);
    final List<String> chunks = chunkDocument(text);
    final String addedAt = clock.now().toIso8601String();

    return _db.transaction(() async {
      final Document? previous = await (_db.select(
        _db.documents,
      )..where((Documents d) => d.path.equals(path))).getSingleOrNull();
      final String id = previous?.id ?? _newId();
      final String title = previous?.title ?? _defaultTitle(path);
      if (previous == null) {
        await _db
            .into(_db.documents)
            .insert(
              DocumentsCompanion.insert(
                id: id,
                title: title,
                path: path,
                addedAt: addedAt,
              ),
            );
      } else {
        // Suppression puis insertion : `INSERT OR REPLACE` laisserait des
        // lignes en double dans l'index plein texte.
        await (_db.delete(
          _db.documentChunks,
        )..where((DocumentChunks c) => c.documentId.equals(id))).go();
        await (_db.update(_db.documents)
              ..where((Documents d) => d.id.equals(id)))
            .write(DocumentsCompanion(addedAt: Value<String>(addedAt)));
      }
      for (int i = 0; i < chunks.length; i++) {
        await _db
            .into(_db.documentChunks)
            .insert(
              DocumentChunksCompanion.insert(
                id: '$id-$i',
                documentId: id,
                position: i,
                content: chunks[i],
              ),
            );
      }
      return LibraryDocument(
        id: id,
        title: title,
        type: type,
        addedAt: DateTime.parse(addedAt),
        excerptCount: chunks.length,
        path: path,
      );
    });
  }

  /// Documents, le plus récent d'abord.
  Future<List<LibraryDocument>> list() async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT d.id, d.title, d.path, d.added_at, '
          '(SELECT count(*) FROM document_chunks c WHERE c.document_id = d.id) '
          'AS n FROM documents d ORDER BY d.added_at DESC',
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.documents,
            _db.documentChunks,
          },
        )
        .get();
    return <LibraryDocument>[
      for (final QueryRow r in rows)
        LibraryDocument(
          id: r.read<String>('id'),
          title: r.read<String>('title'),
          type: _typeOrTxt(r.read<String>('path')),
          addedAt: DateTime.parse(r.read<String>('added_at')),
          excerptCount: r.read<int>('n'),
          path: r.read<String>('path'),
        ),
    ];
  }

  /// Renomme [id] ; un titre vide garde l'ancien.
  Future<void> rename(String id, String title) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await (_db.update(_db.documents)..where((Documents d) => d.id.equals(id)))
        .write(DocumentsCompanion(title: Value<String>(trimmed)));
  }

  /// Supprime [id], ses morceaux et leur index (triggers).
  Future<void> delete(String id) =>
      (_db.delete(_db.documents)..where((Documents d) => d.id.equals(id))).go();

  /// Meilleurs extraits pour [question], du plus pertinent au moins
  /// pertinent. Mots vides et ponctuation ignorés.
  Future<List<DocumentExcerpt>> search(String question, {int limit = 5}) async {
    final List<String> terms = searchTerms(question);
    if (terms.isEmpty) return <DocumentExcerpt>[];
    final List<DocumentSearchResult> hits = await DocumentDao(
      _db,
    ).search(terms.join(' '), limit: limit);
    return <DocumentExcerpt>[
      for (final DocumentSearchResult h in hits)
        DocumentExcerpt(
          documentId: h.documentId,
          documentTitle: h.documentTitle,
          text: excerptAround(h.content, terms),
        ),
    ];
  }

  Future<String> _read(String path, DocumentType type) async {
    try {
      if (type == DocumentType.pdf) {
        return await _pdfChannel.invokeMethod<String>(
              'extractText',
              <String, Object?>{'path': path},
            ) ??
            '';
      }
      return await File(path).readAsString();
    } on PlatformException {
      throw UnreadableDocumentException(path);
    } on MissingPluginException {
      throw UnreadableDocumentException(path);
    } on FileSystemException {
      throw UnreadableDocumentException(path);
    } on FormatException {
      // Octets qui ne sont pas de l'UTF-8.
      throw UnreadableDocumentException(path);
    }
  }

  static DocumentType _typeOf(String path) {
    final String name = _fileName(path);
    final int dot = name.lastIndexOf('.');
    final DocumentType? type = dot <= 0
        ? null
        : DocumentType.values.asNameMap()[name
              .substring(dot + 1)
              .toLowerCase()];
    if (type == null) throw UnsupportedDocumentTypeException(path);
    return type;
  }

  static DocumentType _typeOrTxt(String path) {
    try {
      return _typeOf(path);
    } on UnsupportedDocumentTypeException {
      return DocumentType.txt;
    }
  }

  static String _fileName(String path) =>
      path.split(Platform.pathSeparator).last;

  static String _defaultTitle(String path) {
    final String name = _fileName(path);
    return name.substring(0, name.lastIndexOf('.'));
  }

  static final Random _random = Random();

  static String _newId() =>
      'doc-${clock.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
}

/// Mots vides français retirés d'une question (forme sans accent).
const Set<String> _stopWords = <String>{
  'le', 'la', 'les', 'l', 'de', 'des', 'du', 'd', 'un', 'une', 'et', 'est', //
  'que', 'qu', 'quel', 'quelle', 'quels', 'quelles', 'ce', 'c', 'il', //
  'elle', 'on', 'nous', 'vous', 'a', 'au', 'aux', 'en', 'pour', 'sur', //
  'dans', 'avec', 'ne', 'pas', 't', 's', 'y', 'qui', 'quoi', 'ou', 'se', //
  'sa', 'son', 'ses', 'je', 'j', 'tu', 'n', 'm', 'ils', 'elles', 'ces', //
};

/// Termes utiles de [question] : minuscules, sans accent ni mot vide.
List<String> searchTerms(String question) => <String>{
  for (final RegExpMatch m in RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(question))
    if (fold(m[0]!) case final String w when !_stopWords.contains(w)) w,
}.toList();

/// Passage de [text] d'au plus [kMaxExcerptChars] caractères, centré sur le
/// premier des [terms] trouvé (début gardé si le passage y est).
String excerptAround(String text, List<String> terms) {
  if (text.length <= kMaxExcerptChars) return text;
  final String folded = fold(text);
  final int hit = terms
      .map(folded.indexOf)
      .where((int i) => i >= 0)
      .fold(-1, (int best, int i) => best < 0 || i < best ? i : best);
  const int room = kMaxExcerptChars - 2;
  final int start = hit < 0 ? 0 : max(0, hit - room ~/ 3);
  if (start == 0) return '${text.substring(0, kMaxExcerptChars - 1)}…';
  if (start + room >= text.length) {
    return '…${text.substring(text.length - (kMaxExcerptChars - 1))}';
  }
  return '…${text.substring(start, start + room)}…';
}

const Map<String, String> _accents = <String, String>{
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', //
  'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', //
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', //
  'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ÿ': 'y', 'ý': 'y', //
};

/// Minuscules sans accent, même longueur que [s] (indices conservés).
String fold(String s) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    final String lower = c.toLowerCase();
    final String one = lower.length == 1 ? lower : c;
    out.write(_accents[one] ?? one);
  }
  return out.toString();
}
