// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uvx_available.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Vérifie si `uvx` est disponible sur le PATH au démarrage.
///
/// Utilisé pour décider d'afficher ou non l'écran d'onboarding.

@ProviderFor(uvxAvailable)
const uvxAvailableProvider = UvxAvailableProvider._();

/// Vérifie si `uvx` est disponible sur le PATH au démarrage.
///
/// Utilisé pour décider d'afficher ou non l'écran d'onboarding.

final class UvxAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Vérifie si `uvx` est disponible sur le PATH au démarrage.
  ///
  /// Utilisé pour décider d'afficher ou non l'écran d'onboarding.
  const UvxAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uvxAvailableProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uvxAvailableHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return uvxAvailable(ref);
  }
}

String _$uvxAvailableHash() => r'bd58ab4819e2d3da8486c474b165ad0d75eea86a';
