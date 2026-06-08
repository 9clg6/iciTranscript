import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/datasources/local/session.local.data_source.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session.local.data_source.provider.g.dart';

/// Provider pour [SessionLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des sessions de transcription.
@riverpod
SessionLocalDataSource sessionLocalDataSource(Ref ref) {
  final AppDatabase db = ref.watch(databaseProvider);
  final SessionDao dao = SessionDao(db);
  return SessionLocalDataSourceImpl(sessionDao: dao);
}
