// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_dio.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Client HTTP de toutes les requêtes LLM (délais : voir `postLines`).

@ProviderFor(llmDio)
const llmDioProvider = LlmDioProvider._();

/// Client HTTP de toutes les requêtes LLM (délais : voir `postLines`).

final class LlmDioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  /// Client HTTP de toutes les requêtes LLM (délais : voir `postLines`).
  const LlmDioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'llmDioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$llmDioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return llmDio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$llmDioHash() => r'f736ccf70e147f093869d975a4e243e48c69a4ee';
