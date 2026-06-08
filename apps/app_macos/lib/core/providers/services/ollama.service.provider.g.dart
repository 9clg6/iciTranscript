// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ollama.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [OllamaService].

@ProviderFor(ollamaService)
const ollamaServiceProvider = OllamaServiceProvider._();

/// Provider singleton pour [OllamaService].

final class OllamaServiceProvider
    extends $FunctionalProvider<OllamaService, OllamaService, OllamaService>
    with $Provider<OllamaService> {
  /// Provider singleton pour [OllamaService].
  const OllamaServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ollamaServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ollamaServiceHash();

  @$internal
  @override
  $ProviderElement<OllamaService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OllamaService create(Ref ref) {
    return ollamaService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OllamaService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OllamaService>(value),
    );
  }
}

String _$ollamaServiceHash() => r'e72357b072d5ae69e1c60b64ef0645d6d3d4dd87';
