import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcription.remote.data_source.provider.g.dart';

/// Provider pour [TranscriptionRemoteDataSource].
///
/// Fournit l'implementation WebSocket (deux flux : micro + système) pour la
/// communication avec voxmlx-serve (transcription temps réel).
@riverpod
TranscriptionRemoteDataSource transcriptionRemoteDataSource(Ref ref) {
  final TranscriptionRemoteDataSourceImpl ds =
      TranscriptionRemoteDataSourceImpl();
  ref.onDispose(ds.dispose);
  return ds;
}
