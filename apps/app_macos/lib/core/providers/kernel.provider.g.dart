// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kernel.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Initialise les dependances au demarrage de l'application.
///
/// Le serveur ML (voxmlx-serve) est demarre par [LiveTranscriptionService]
/// au moment ou l'utilisateur lance un enregistrement.
/// Ollama est initialise separement par [OllamaSetupViewModel].

@ProviderFor(kernel)
const kernelProvider = KernelProvider._();

/// Initialise les dependances au demarrage de l'application.
///
/// Le serveur ML (voxmlx-serve) est demarre par [LiveTranscriptionService]
/// au moment ou l'utilisateur lance un enregistrement.
/// Ollama est initialise separement par [OllamaSetupViewModel].

final class KernelProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Initialise les dependances au demarrage de l'application.
  ///
  /// Le serveur ML (voxmlx-serve) est demarre par [LiveTranscriptionService]
  /// au moment ou l'utilisateur lance un enregistrement.
  /// Ollama est initialise separement par [OllamaSetupViewModel].
  const KernelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'kernelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$kernelHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return kernel(ref);
  }
}

String _$kernelHash() => r'482defeffe9277afae93a00eee75b12229f2d9bd';
