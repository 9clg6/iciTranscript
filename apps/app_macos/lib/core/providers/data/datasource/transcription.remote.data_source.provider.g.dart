// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription.remote.data_source.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [TranscriptionRemoteDataSource].
///
/// Deux flux (micro + système), chacun routé vers voxmlx-serve sur ce Mac
/// ou vers Mistral en ligne selon l'adresse que passe le service (moteur
/// choisi) ; la couche de fiabilité est la même.

@ProviderFor(transcriptionRemoteDataSource)
const transcriptionRemoteDataSourceProvider =
    TranscriptionRemoteDataSourceProvider._();

/// Provider pour [TranscriptionRemoteDataSource].
///
/// Deux flux (micro + système), chacun routé vers voxmlx-serve sur ce Mac
/// ou vers Mistral en ligne selon l'adresse que passe le service (moteur
/// choisi) ; la couche de fiabilité est la même.

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
  /// Deux flux (micro + système), chacun routé vers voxmlx-serve sur ce Mac
  /// ou vers Mistral en ligne selon l'adresse que passe le service (moteur
  /// choisi) ; la couche de fiabilité est la même.
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
    r'bc991374a93216e32cb1062f93e11e333a2251c1';
