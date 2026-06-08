import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:core_data/datasources/local/impl/transcript.local.data_source.impl.dart';
import 'package:core_data/datasources/local/transcript.local.data_source.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcript.local.data_source.provider.g.dart';

/// Provider pour [TranscriptLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des segments de transcription.
@riverpod
TranscriptLocalDataSource transcriptLocalDataSource(Ref ref) {
  final AppDatabase db = ref.watch(databaseProvider);
  final TranscriptSegmentDao dao = TranscriptSegmentDao(db);
  return TranscriptLocalDataSourceImpl(transcriptSegmentDao: dao);
}
