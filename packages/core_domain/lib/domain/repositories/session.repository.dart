import 'package:core_domain/domain/entities/session.entity.dart';

/// Contrat du repository de sessions de transcription.
abstract interface class SessionRepository {
  /// Recupere toutes les sessions.
  Future<List<SessionEntity>> getAll();

  /// Recupere une session par son identifiant.
  Future<SessionEntity?> getById(String id);

  /// Cree une nouvelle session.
  Future<SessionEntity> create(SessionEntity session);

  /// Met a jour une session existante.
  Future<SessionEntity> update(SessionEntity session);

  /// Ajoute de l'audio en ligne aux compteurs de la session (additif ;
  /// [update] ne les reecrit jamais). Session absente : rien.
  Future<void> addCloudUsage(
    String sessionId, {
    int realtimeMs = 0,
    int batchMs = 0,
  });

  /// Supprime une session par son identifiant.
  Future<void> delete(String id);

  /// Stream reactif de toutes les sessions.
  Stream<List<SessionEntity>> watchAll();
}
