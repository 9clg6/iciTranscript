import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';

part 'document.dao.g.dart';

/// Morceau de document trouve par [DocumentDao.search].
class DocumentSearchResult {
  /// Cree un [DocumentSearchResult].
  const DocumentSearchResult({
    required this.chunkId,
    required this.documentId,
    required this.documentTitle,
    required this.content,
  });

  /// Identifiant du morceau.
  final String chunkId;

  /// Identifiant du document parent.
  final String documentId;

  /// Titre du document parent.
  final String documentTitle;

  /// Texte du morceau.
  final String content;
}

/// DAO pour les documents sources et leur recherche plein texte.
@DriftAccessor(tables: <Type>[Documents, DocumentChunks])
class DocumentDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentDaoMixin {
  /// Cree une instance de [DocumentDao].
  DocumentDao(super.db);

  /// Morceaux les plus pertinents pour [query], du meilleur au moins bon.
  ///
  /// Chaque mot de la requete est cherche tel quel (guillemets FTS5) et un
  /// seul suffit : une question en langage naturel contient des mots absents
  /// des documents. Casse et accents ignores.
  Future<List<DocumentSearchResult>> search(
    String query, {
    int limit = 5,
  }) async {
    final List<String> words = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query).map((RegExpMatch m) => '"${m[0]}"').toList();
    if (words.isEmpty) return <DocumentSearchResult>[];

    return customSelect(
      'SELECT c.id, c.document_id, d.title, c.content '
      'FROM document_chunks_fts f '
      'JOIN document_chunks c ON c.id = f.chunk_id '
      'JOIN documents d ON d.id = c.document_id '
      'WHERE document_chunks_fts MATCH ? '
      'ORDER BY f.rank LIMIT ?',
      variables: <Variable<Object>>[
        Variable<String>(words.join(' OR ')),
        Variable<int>(limit),
      ],
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
        documents,
        documentChunks,
      },
    ).map((QueryRow row) {
      return DocumentSearchResult(
        chunkId: row.read<String>('id'),
        documentId: row.read<String>('document_id'),
        documentTitle: row.read<String>('title'),
        content: row.read<String>('content'),
      );
    }).get();
  }
}
