// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ollama.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [OllamaService] : le démon passe par le registre
/// des serveurs de l'app (seul celui qu'on a lancé est arrêté).

@ProviderFor(ollamaService)
const ollamaServiceProvider = OllamaServiceProvider._();

/// Provider singleton pour [OllamaService] : le démon passe par le registre
/// des serveurs de l'app (seul celui qu'on a lancé est arrêté).

final class OllamaServiceProvider
    extends $FunctionalProvider<OllamaService, OllamaService, OllamaService>
    with $Provider<OllamaService> {
  /// Provider singleton pour [OllamaService] : le démon passe par le registre
  /// des serveurs de l'app (seul celui qu'on a lancé est arrêté).
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

String _$ollamaServiceHash() => r'c3c0caf890ee94273ce5ef639b049534b2557929';
