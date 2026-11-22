// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_key_store.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [ApiKeyStore] (trousseau macOS).

@ProviderFor(apiKeyStore)
const apiKeyStoreProvider = ApiKeyStoreProvider._();

/// Provider singleton pour [ApiKeyStore] (trousseau macOS).

final class ApiKeyStoreProvider
    extends $FunctionalProvider<ApiKeyStore, ApiKeyStore, ApiKeyStore>
    with $Provider<ApiKeyStore> {
  /// Provider singleton pour [ApiKeyStore] (trousseau macOS).
  const ApiKeyStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiKeyStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiKeyStoreHash();

  @$internal
  @override
  $ProviderElement<ApiKeyStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ApiKeyStore create(Ref ref) {
    return apiKeyStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApiKeyStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApiKeyStore>(value),
    );
  }
}

String _$apiKeyStoreHash() => r'5d3febfb520d0791274b99c6298fdc3115a63562';
