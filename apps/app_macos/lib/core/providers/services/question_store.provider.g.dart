// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'question_store.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Questions détectées gardées avec la note, sur la base de l'app.

@ProviderFor(questionStore)
const questionStoreProvider = QuestionStoreProvider._();

/// Questions détectées gardées avec la note, sur la base de l'app.

final class QuestionStoreProvider
    extends $FunctionalProvider<QuestionStore, QuestionStore, QuestionStore>
    with $Provider<QuestionStore> {
  /// Questions détectées gardées avec la note, sur la base de l'app.
  const QuestionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'questionStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$questionStoreHash();

  @$internal
  @override
  $ProviderElement<QuestionStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  QuestionStore create(Ref ref) {
    return questionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuestionStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuestionStore>(value),
    );
  }
}

String _$questionStoreHash() => r'15929a1fc44787c63550ee781f30e545d376d11d';
