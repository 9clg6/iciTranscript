// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_llm_provider.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Fournisseur LLM actif, construit avec sa cle du trousseau.
///
/// A invalider apres l'ecriture ou la suppression d'une cle.

@ProviderFor(activeLlmProvider)
const activeLlmProviderProvider = ActiveLlmProviderProvider._();

/// Fournisseur LLM actif, construit avec sa cle du trousseau.
///
/// A invalider apres l'ecriture ou la suppression d'une cle.

final class ActiveLlmProviderProvider
    extends
        $FunctionalProvider<
          AsyncValue<LlmProvider>,
          LlmProvider,
          FutureOr<LlmProvider>
        >
    with $FutureModifier<LlmProvider>, $FutureProvider<LlmProvider> {
  /// Fournisseur LLM actif, construit avec sa cle du trousseau.
  ///
  /// A invalider apres l'ecriture ou la suppression d'une cle.
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

String _$activeLlmProviderHash() => r'9103a6eec5b18aebd614dbaa8e865881d3161bbd';
