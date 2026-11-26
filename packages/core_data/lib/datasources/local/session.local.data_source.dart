import 'package:core_data/model/local/session.local.model.dart';

/// Contrat de la source de donnees locale pour les sessions.
abstract interface class SessionLocalDataSource {
  /// Recupere toutes les sessions.
  Future<List<SessionLocalModel>> getAll();

  /// Recupere une session par son identifiant.
  Future<SessionLocalModel?> getById(String id);

  /// Insere une nouvelle session.
  Future<void> insert(SessionLocalModel session);

  /// Met a jour une session existante.
  Future<void> update(SessionLocalModel session);

  /// Ajoute de l'audio en ligne aux compteurs de la session (additif).
  Future<void> addCloudUsage(String id, {int realtimeMs = 0, int batchMs = 0});

  /// Supprime une session par son identifiant.
  Future<void> delete(String id);

  /// Stream reactif de toutes les sessions.
  Stream<List<SessionLocalModel>> watchAll();
}
