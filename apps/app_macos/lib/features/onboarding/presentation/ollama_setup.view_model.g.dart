// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ollama_setup.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel du modèle local (moteur Ollama + modèle choisi dans Réglages,
/// Mistral par défaut).
///
/// [build] détecte seulement (aucun téléchargement) ; [install] lance
/// l'installation (~106 Mo + ~4 Go) à la demande, depuis Réglages.

@ProviderFor(OllamaSetupViewModel)
const ollamaSetupViewModelProvider = OllamaSetupViewModelProvider._();

/// ViewModel du modèle local (moteur Ollama + modèle choisi dans Réglages,
/// Mistral par défaut).
///
/// [build] détecte seulement (aucun téléchargement) ; [install] lance
/// l'installation (~106 Mo + ~4 Go) à la demande, depuis Réglages.
final class OllamaSetupViewModelProvider
    extends $NotifierProvider<OllamaSetupViewModel, OllamaSetupState> {
  /// ViewModel du modèle local (moteur Ollama + modèle choisi dans Réglages,
  /// Mistral par défaut).
  ///
  /// [build] détecte seulement (aucun téléchargement) ; [install] lance
  /// l'installation (~106 Mo + ~4 Go) à la demande, depuis Réglages.
  const OllamaSetupViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ollamaSetupViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ollamaSetupViewModelHash();

  @$internal
  @override
  OllamaSetupViewModel create() => OllamaSetupViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OllamaSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OllamaSetupState>(value),
    );
  }
}

String _$ollamaSetupViewModelHash() =>
    r'fa912c0745ab165cfec3879dffa6fd0a6d9f0472';

/// ViewModel du modèle local (moteur Ollama + modèle choisi dans Réglages,
/// Mistral par défaut).
///
/// [build] détecte seulement (aucun téléchargement) ; [install] lance
/// l'installation (~106 Mo + ~4 Go) à la demande, depuis Réglages.

abstract class _$OllamaSetupViewModel extends $Notifier<OllamaSetupState> {
  OllamaSetupState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<OllamaSetupState, OllamaSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OllamaSetupState, OllamaSetupState>,
              OllamaSetupState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
