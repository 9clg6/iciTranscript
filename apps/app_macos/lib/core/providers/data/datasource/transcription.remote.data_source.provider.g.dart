// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription.remote.data_source.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [TranscriptionRemoteDataSource].
///
/// Fournit l'implementation WebSocket (deux flux : micro + système) pour la
/// communication avec voxmlx-serve (transcription temps réel).

@ProviderFor(transcriptionRemoteDataSource)
const transcriptionRemoteDataSourceProvider =
    TranscriptionRemoteDataSourceProvider._();

/// Provider pour [TranscriptionRemoteDataSource].
///
/// Fournit l'implementation WebSocket (deux flux : micro + système) pour la
/// communication avec voxmlx-serve (transcription temps réel).

final class TranscriptionRemoteDataSourceProvider
    extends
        $FunctionalProvider<
          TranscriptionRemoteDataSource,
          TranscriptionRemoteDataSource,
          TranscriptionRemoteDataSource
        >
    with $Provider<TranscriptionRemoteDataSource> {
  /// Provider pour [TranscriptionRemoteDataSource].
  ///
  /// Fournit l'implementation WebSocket (deux flux : micro + système) pour la
  /// communication avec voxmlx-serve (transcription temps réel).
  const TranscriptionRemoteDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptionRemoteDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptionRemoteDataSourceHash();

  @$internal
  @override
  $ProviderElement<TranscriptionRemoteDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptionRemoteDataSource create(Ref ref) {
    return transcriptionRemoteDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptionRemoteDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptionRemoteDataSource>(
        value,
      ),
    );
  }
}

String _$transcriptionRemoteDataSourceHash() =>
    r'f097adb5cf224ba70c2a5835a446c0255f4e57c0';
