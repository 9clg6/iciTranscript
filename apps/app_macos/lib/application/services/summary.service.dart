import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/summary.dao.dart';
import 'package:core_foundation/logging/logger.dart';

/// Service de gestion des résumés IA des sessions.
final class SummaryService {
  /// Cree une instance de [SummaryService].
  SummaryService({required SummaryDao summaryDao}) : _dao = summaryDao;

  final SummaryDao _dao;
  final Log _log = Log.named('SummaryService');

  /// Sauvegarde un résumé pour une session.
  ///
  /// Une seule ligne par session : on purge les éventuelles lignes existantes
  /// (y compris d'anciens formats) puis on insère avec `id == sessionId`.
  /// `getBySessionId` utilise `getSingleOrNull` qui lèverait sinon en présence
  /// de doublons.
  Future<void> saveSummary({
    required String sessionId,
    required String content,
    String model = 'mistral',
  }) async {
    _log.info('Sauvegarde résumé pour session $sessionId');
    await _dao.deleteBySessionId(sessionId);
    await _dao.insertSummary(
      SummariesCompanion.insert(
        id: sessionId,
        sessionId: sessionId,
        content: content,
        model: model,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Récupère le résumé d'une session, ou null si absent.
  Future<String?> getSummaryForSession(String sessionId) async {
    final Summary? row = await _dao.getBySessionId(sessionId);
    return row?.content;
  }

  /// Supprime le résumé d'une session.
  Future<void> deleteSummaryForSession(String sessionId) async {
    _log.info('Suppression résumé pour session $sessionId');
    await _dao.deleteBySessionId(sessionId);
  }
}
