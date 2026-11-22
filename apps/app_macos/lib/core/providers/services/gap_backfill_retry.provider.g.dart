// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gap_backfill_retry.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Rattrapage des repères depuis les WAV, avec reprise quand le serveur de
/// transcription revient (une seule instance : un seul fichier d'attente).

@ProviderFor(gapBackfillRetry)
const gapBackfillRetryProvider = GapBackfillRetryProvider._();

/// Rattrapage des repères depuis les WAV, avec reprise quand le serveur de
/// transcription revient (une seule instance : un seul fichier d'attente).

final class GapBackfillRetryProvider
    extends
        $FunctionalProvider<
          GapBackfillRetry,
          GapBackfillRetry,
          GapBackfillRetry
        >
    with $Provider<GapBackfillRetry> {
  /// Rattrapage des repères depuis les WAV, avec reprise quand le serveur de
  /// transcription revient (une seule instance : un seul fichier d'attente).
  const GapBackfillRetryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gapBackfillRetryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gapBackfillRetryHash();

  @$internal
  @override
  $ProviderElement<GapBackfillRetry> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GapBackfillRetry create(Ref ref) {
    return gapBackfillRetry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GapBackfillRetry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GapBackfillRetry>(value),
    );
  }
}

String _$gapBackfillRetryHash() => r'ed229d8ee2cdff0ae206a4710afbe529ddeb6e0a';
