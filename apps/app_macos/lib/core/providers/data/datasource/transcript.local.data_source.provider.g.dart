// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript.local.data_source.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [TranscriptLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des segments de transcription.

@ProviderFor(transcriptLocalDataSource)
const transcriptLocalDataSourceProvider = TranscriptLocalDataSourceProvider._();

/// Provider pour [TranscriptLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des segments de transcription.

final class TranscriptLocalDataSourceProvider
    extends
        $FunctionalProvider<
          TranscriptLocalDataSource,
          TranscriptLocalDataSource,
          TranscriptLocalDataSource
        >
    with $Provider<TranscriptLocalDataSource> {
  /// Provider pour [TranscriptLocalDataSource].
  ///
  /// Fournit l'implementation basee sur Drift/SQLite pour la persistance
  /// des segments de transcription.
  const TranscriptLocalDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptLocalDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptLocalDataSourceHash();

  @$internal
  @override
  $ProviderElement<TranscriptLocalDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptLocalDataSource create(Ref ref) {
    return transcriptLocalDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptLocalDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptLocalDataSource>(value),
    );
  }
}

String _$transcriptLocalDataSourceHash() =>
    r'f1632fdb34c010f3ac34c04255646e9baa317eb4';
