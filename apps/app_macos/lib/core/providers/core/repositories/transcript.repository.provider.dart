import 'package:core_data/datasources/local/transcript.local.data_source.dart';
import 'package:core_data/repositories/transcript.repository.impl.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:ici_transcript/core/providers/data/datasource/transcript.local.data_source.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcript.repository.provider.g.dart';

/// Provider pour [TranscriptRepository].
///
/// Fournit l'implementation [TranscriptRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des segments.
@riverpod
TranscriptRepository transcriptRepository(Ref ref) {
  final TranscriptLocalDataSource localDataSource = ref.watch(
    transcriptLocalDataSourceProvider,
  );
  return TranscriptRepositoryImpl(transcriptLocalDataSource: localDataSource);
}
