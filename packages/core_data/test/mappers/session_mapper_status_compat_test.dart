import 'package:core_data/mappers/session.mapper.dart';
import 'package:core_data/model/local/session.local.model.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:test/test.dart';

/// Tour 3, point 5 : plusieurs versions de l'app peuvent partager le même
/// fichier de base. Un statut inconnu de cette version (écrit par une plus
/// récente) ne doit pas faire échouer la lecture : il est lu `completed`.
void main() {
  SessionLocalModel stored(String status) => SessionLocalModel(
    id: 'session-1',
    title: 'Réunion',
    createdAt: '2026-11-22T10:00:00.000',
    updatedAt: '2026-11-22T11:00:00.000',
    durationSeconds: 3600,
    status: status,
  );

  test('un statut inconnu est lu comme completed, sans erreur', () {
    final SessionEntity entity = stored('archived').toEntity();

    expect(entity.status, SessionStatus.completed);
    expect(entity.id, 'session-1');
    expect(entity.durationSeconds, 3600);
  });

  test('un statut vide est lu comme completed, sans erreur', () {
    expect(stored('').toEntity().status, SessionStatus.completed);
  });

  test('chaque statut connu, dont interrupted, est relu tel quel', () {
    for (final SessionStatus status in SessionStatus.values) {
      expect(stored(status.name).toEntity().status, status);
    }
  });

  test('interrupted s écrit sous ce nom en base', () {
    final SessionLocalModel model = SessionEntity(
      id: 'session-1',
      title: 'Réunion',
      createdAt: DateTime(2026, 11, 22, 10),
      updatedAt: DateTime(2026, 11, 22, 11),
      status: SessionStatus.interrupted,
    ).toLocalModel();

    expect(model.status, 'interrupted');
  });
}
