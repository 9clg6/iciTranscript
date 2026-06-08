// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [TranslationService].

@ProviderFor(translationService)
const translationServiceProvider = TranslationServiceProvider._();

/// Provider singleton pour [TranslationService].

final class TranslationServiceProvider
    extends
        $FunctionalProvider<
          TranslationService,
          TranslationService,
          TranslationService
        >
    with $Provider<TranslationService> {
  /// Provider singleton pour [TranslationService].
  const TranslationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationServiceHash();

  @$internal
  @override
  $ProviderElement<TranslationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationService create(Ref ref) {
    return translationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationService>(value),
    );
  }
}

String _$translationServiceHash() =>
    r'c4f8efcf67f02dd238410139060ffbdfc70354b6';
