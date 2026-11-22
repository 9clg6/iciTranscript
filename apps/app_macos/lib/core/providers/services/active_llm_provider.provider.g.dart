// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_llm_provider.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Fournisseur LLM actif : choix de Réglages (prefs.json) et clé du
/// trousseau, avec le repli de [LlmProviderSelection].
///
/// Lu une fois puis gardé : Réglages l'invalide après chaque changement de
/// clé, de fournisseur, de modèle ou d'autorisation d'envoi.

@ProviderFor(activeLlmProvider)
const activeLlmProviderProvider = ActiveLlmProviderProvider._();

/// Fournisseur LLM actif : choix de Réglages (prefs.json) et clé du
/// trousseau, avec le repli de [LlmProviderSelection].
///
/// Lu une fois puis gardé : Réglages l'invalide après chaque changement de
/// clé, de fournisseur, de modèle ou d'autorisation d'envoi.

final class ActiveLlmProviderProvider
    extends
        $FunctionalProvider<
          AsyncValue<LlmProvider>,
          LlmProvider,
          FutureOr<LlmProvider>
        >
    with $FutureModifier<LlmProvider>, $FutureProvider<LlmProvider> {
  /// Fournisseur LLM actif : choix de Réglages (prefs.json) et clé du
  /// trousseau, avec le repli de [LlmProviderSelection].
  ///
  /// Lu une fois puis gardé : Réglages l'invalide après chaque changement de
  /// clé, de fournisseur, de modèle ou d'autorisation d'envoi.
  const ActiveLlmProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeLlmProviderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeLlmProviderHash();

  @$internal
  @override
  $FutureProviderElement<LlmProvider> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LlmProvider> create(Ref ref) {
    return activeLlmProvider(ref);
  }
}

String _$activeLlmProviderHash() => r'0e616c4f82b74d0078741d8e96da56e9de6ae01d';
