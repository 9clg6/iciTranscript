import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/datasources/local/session.local.data_source.dart';
import 'package:core_data/model/local/session.local.model.dart';

/// Implementation de [SessionLocalDataSource] utilisant Drift/SQLite.
final class SessionLocalDataSourceImpl implements SessionLocalDataSource {
  /// Cree une instance de [SessionLocalDataSourceImpl].
  SessionLocalDataSourceImpl({required SessionDao sessionDao})
    : _sessionDao = sessionDao;

  final SessionDao _sessionDao;

  @override
  Future<List<SessionLocalModel>> getAll() async {
    final List<Session> rows = await _sessionDao.getAll();
    return rows.map(_toModel).toList();
  }

  @override
  Future<SessionLocalModel?> getById(String id) async {
    final Session? row = await _sessionDao.getById(id);
    return row == null ? null : _toModel(row);
  }

  @override
  Future<void> insert(SessionLocalModel session) {
    return _sessionDao.insertSession(
      SessionsCompanion.insert(
        id: session.id,
        title: session.title,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        durationSeconds: Value<int?>(session.durationSeconds),
        status: session.status,
        calendarEventId: Value<String?>(session.calendarEventId),
        calendarEventTitle: Value<String?>(session.calendarEventTitle),
        attendees: Value<String?>(session.attendees),
      ),
    );
  }

  @override
  Future<void> update(SessionLocalModel session) {
    return _sessionDao.updateSession(
      SessionsCompanion(
        id: Value<String>(session.id),
        title: Value<String>(session.title),
        createdAt: Value<String>(session.createdAt),
        updatedAt: Value<String>(session.updatedAt),
        durationSeconds: Value<int?>(session.durationSeconds),
        status: Value<String>(session.status),
        calendarEventId: Value<String?>(session.calendarEventId),
        calendarEventTitle: Value<String?>(session.calendarEventTitle),
        attendees: Value<String?>(session.attendees),
      ),
    );
  }

  @override
  Future<void> delete(String id) {
    return _sessionDao.deleteById(id);
  }

  @override
  Stream<List<SessionLocalModel>> watchAll() {
    return _sessionDao.watchAll().map(
      (List<Session> rows) => rows.map(_toModel).toList(),
    );
  }

  static SessionLocalModel _toModel(Session row) => SessionLocalModel(
    id: row.id,
    title: row.title,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    durationSeconds: row.durationSeconds,
    status: row.status,
    calendarEventId: row.calendarEventId,
    calendarEventTitle: row.calendarEventTitle,
    attendees: row.attendees,
  );
}
