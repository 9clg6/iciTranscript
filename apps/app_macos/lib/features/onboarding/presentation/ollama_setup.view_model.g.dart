// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ollama_setup.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel du processus de configuration initiale d'Ollama.
///
/// Surveille et déclenche le téléchargement du binaire Ollama et du modèle
/// Mistral si nécessaire. Appelé une seule fois au démarrage de l'app.

@ProviderFor(OllamaSetupViewModel)
const ollamaSetupViewModelProvider = OllamaSetupViewModelProvider._();

/// ViewModel du processus de configuration initiale d'Ollama.
///
/// Surveille et déclenche le téléchargement du binaire Ollama et du modèle
/// Mistral si nécessaire. Appelé une seule fois au démarrage de l'app.
final class OllamaSetupViewModelProvider
    extends $NotifierProvider<OllamaSetupViewModel, OllamaSetupState> {
  /// ViewModel du processus de configuration initiale d'Ollama.
  ///
  /// Surveille et déclenche le téléchargement du binaire Ollama et du modèle
  /// Mistral si nécessaire. Appelé une seule fois au démarrage de l'app.
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
    r'd6465edc20f0c12fbc936beb96c3a55545547186';

/// ViewModel du processus de configuration initiale d'Ollama.
///
/// Surveille et déclenche le téléchargement du binaire Ollama et du modèle
/// Mistral si nécessaire. Appelé une seule fois au démarrage de l'app.

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
