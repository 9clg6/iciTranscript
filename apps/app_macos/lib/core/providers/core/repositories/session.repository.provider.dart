import 'package:core_data/datasources/local/session.local.data_source.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:ici_transcript/core/providers/data/datasource/session.local.data_source.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session.repository.provider.g.dart';

/// Provider pour [SessionRepository].
///
/// Fournit l'implementation [SessionRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des sessions.
@riverpod
SessionRepository sessionRepository(Ref ref) {
  final SessionLocalDataSource localDataSource = ref.watch(
    sessionLocalDataSourceProvider,
  );
  return SessionRepositoryImpl(sessionLocalDataSource: localDataSource);
}
