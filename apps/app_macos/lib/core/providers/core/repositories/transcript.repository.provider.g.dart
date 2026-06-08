// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript.repository.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [TranscriptRepository].
///
/// Fournit l'implementation [TranscriptRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des segments.

@ProviderFor(transcriptRepository)
const transcriptRepositoryProvider = TranscriptRepositoryProvider._();

/// Provider pour [TranscriptRepository].
///
/// Fournit l'implementation [TranscriptRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des segments.

final class TranscriptRepositoryProvider
    extends
        $FunctionalProvider<
          TranscriptRepository,
          TranscriptRepository,
          TranscriptRepository
        >
    with $Provider<TranscriptRepository> {
  /// Provider pour [TranscriptRepository].
  ///
  /// Fournit l'implementation [TranscriptRepositoryImpl] qui utilise
  /// la source de donnees locale Drift pour la persistance des segments.
  const TranscriptRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranscriptRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptRepository create(Ref ref) {
    return transcriptRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptRepository>(value),
    );
  }
}

String _$transcriptRepositoryHash() =>
    r'bb453fc13dbb43577c882912015a1897b02cd295';
