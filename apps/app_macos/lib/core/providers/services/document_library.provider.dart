import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'document_library.provider.g.dart';

/// Bibliothèque de documents sources, sur la base de l'app.
@riverpod
DocumentLibrary documentLibrary(Ref ref) =>
    DocumentLibrary(ref.watch(databaseProvider));
