// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription_server_arbiter.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Arbitre unique du serveur de transcription : enregistrement > dictée >
/// rattrapage des pertes.

@ProviderFor(transcriptionServerArbiter)
const transcriptionServerArbiterProvider =
    TranscriptionServerArbiterProvider._();

/// Arbitre unique du serveur de transcription : enregistrement > dictée >
/// rattrapage des pertes.

final class TranscriptionServerArbiterProvider
    extends
        $FunctionalProvider<
          TranscriptionServerArbiter,
          TranscriptionServerArbiter,
          TranscriptionServerArbiter
        >
    with $Provider<TranscriptionServerArbiter> {
  /// Arbitre unique du serveur de transcription : enregistrement > dictée >
  /// rattrapage des pertes.
  const TranscriptionServerArbiterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptionServerArbiterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptionServerArbiterHash();

  @$internal
  @override
  $ProviderElement<TranscriptionServerArbiter> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptionServerArbiter create(Ref ref) {
    return transcriptionServerArbiter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptionServerArbiter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptionServerArbiter>(value),
    );
  }
}

String _$transcriptionServerArbiterHash() =>
    r'4dae863bf6f6a1df55a740984e3efa9b0f467c93';
