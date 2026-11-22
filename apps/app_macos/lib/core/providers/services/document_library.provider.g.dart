// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_library.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Bibliothèque de documents sources, sur la base de l'app.

@ProviderFor(documentLibrary)
const documentLibraryProvider = DocumentLibraryProvider._();

/// Bibliothèque de documents sources, sur la base de l'app.

final class DocumentLibraryProvider
    extends
        $FunctionalProvider<DocumentLibrary, DocumentLibrary, DocumentLibrary>
    with $Provider<DocumentLibrary> {
  /// Bibliothèque de documents sources, sur la base de l'app.
  const DocumentLibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'documentLibraryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$documentLibraryHash();

  @$internal
  @override
  $ProviderElement<DocumentLibrary> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DocumentLibrary create(Ref ref) {
    return documentLibrary(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DocumentLibrary value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DocumentLibrary>(value),
    );
  }
}

String _$documentLibraryHash() => r'9dcd86345ec732bb406099eea6d7a902220abfaa';
