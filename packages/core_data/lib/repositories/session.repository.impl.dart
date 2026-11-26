import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';

import 'package:core_data/datasources/local/session.local.data_source.dart';
import 'package:core_data/mappers/session.mapper.dart';
import 'package:core_data/model/local/session.local.model.dart';

/// Implementation de [SessionRepository] utilisant la source de donnees locale.
final class SessionRepositoryImpl implements SessionRepository {
  /// Cree une instance de [SessionRepositoryImpl].
  SessionRepositoryImpl({
    required SessionLocalDataSource sessionLocalDataSource,
  }) : _localDataSource = sessionLocalDataSource;

  final SessionLocalDataSource _localDataSource;

  @override
  Future<List<SessionEntity>> getAll() async {
    final List<SessionLocalModel> localModels = await _localDataSource.getAll();
    return localModels.map((SessionLocalModel m) => m.toEntity()).toList();
  }

  @override
  Future<SessionEntity?> getById(String id) async {
    final SessionLocalModel? localModel = await _localDataSource.getById(id);
    return localModel?.toEntity();
  }

  @override
  Future<SessionEntity> create(SessionEntity session) async {
    final SessionLocalModel localModel = session.toLocalModel();
    await _localDataSource.insert(localModel);
    return session;
  }

  @override
  Future<SessionEntity> update(SessionEntity session) async {
    final SessionLocalModel localModel = session.toLocalModel();
    await _localDataSource.update(localModel);
    return session;
  }

  @override
  Future<void> addCloudUsage(
    String sessionId, {
    int realtimeMs = 0,
    int batchMs = 0,
  }) {
    return _localDataSource.addCloudUsage(
      sessionId,
      realtimeMs: realtimeMs,
      batchMs: batchMs,
    );
  }

  @override
  Future<void> delete(String id) {
    return _localDataSource.delete(id);
  }

  @override
  Stream<List<SessionEntity>> watchAll() {
    return _localDataSource.watchAll().map(
      (List<SessionLocalModel> models) =>
          models.map((SessionLocalModel m) => m.toEntity()).toList(),
    );
  }
}
