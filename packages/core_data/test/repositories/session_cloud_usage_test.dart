import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Prix de la transcription en ligne (2026-11-26) : chaque note garde l'audio
/// facturé par Mistral, en ms, par mode : temps réel (réunion) et batch
/// (rattrapage). L'ajout est ADDITIF : l'arrêt de la réunion puis un
/// rattrapage (tout de suite, ou à un lancement suivant) s'additionnent.
///
/// API supposée :
/// - `SessionEntity.cloudRealtimeMs`, `SessionEntity.cloudBatchMs` (int,
///   `@Default(0)`) ; colonnes `cloud_realtime_ms`, `cloud_batch_ms` ;
/// - `SessionRepository.addCloudUsage(String sessionId, {int realtimeMs =
///   0, int batchMs = 0})`, rend un futur vide : ajoute à ce qui est rangé
///   (sans lire puis réécrire l'entité) ; session absente : rien ;
/// - `update(session)` ne touche jamais l'usage : renommer, lier à
///   l'agenda ou clore une note depuis une entité lue avant un ajout ne
///   l'efface pas.
void main() {
  late AppDatabase db;
  late SessionRepositoryImpl repo;
  final DateTime start = DateTime(2026, 11, 26, 10);

  SessionEntity session({String title = 'Point équipe'}) => SessionEntity(
    id: 's1',
    title: title,
    createdAt: start,
    updatedAt: start,
    status: SessionStatus.active,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SessionRepositoryImpl(
      sessionLocalDataSource: SessionLocalDataSourceImpl(
        sessionDao: SessionDao(db),
      ),
    );
    await repo.create(session());
  });
  tearDown(() => db.close());

  test('une note neuve n a aucun usage en ligne', () async {
    final SessionEntity s = (await repo.getById('s1'))!;
    expect(s.cloudRealtimeMs, 0);
    expect(s.cloudBatchMs, 0);
  });

  test('deux ajouts s additionnent, chaque mode à part', () async {
    await repo.addCloudUsage('s1', realtimeMs: 60000);
    await repo.addCloudUsage('s1', batchMs: 30000);
    await repo.addCloudUsage('s1', realtimeMs: 1500, batchMs: 2500);

    final SessionEntity s = (await repo.getById('s1'))!;
    expect(s.cloudRealtimeMs, 61500);
    expect(s.cloudBatchMs, 32500);
  });

  test('la liste (getAll, watchAll) porte l usage', () async {
    await repo.addCloudUsage('s1', realtimeMs: 90000, batchMs: 12000);

    final SessionEntity listed = (await repo.getAll()).single;
    expect((listed.cloudRealtimeMs, listed.cloudBatchMs), (90000, 12000));
    final SessionEntity watched = (await repo.watchAll().first).single;
    expect((watched.cloudRealtimeMs, watched.cloudBatchMs), (90000, 12000));
  });

  test('update depuis une entité lue avant l ajout (renommage, arrêt) '
      'garde l usage', () async {
    final SessionEntity stale = (await repo.getById('s1'))!;
    await repo.addCloudUsage('s1', realtimeMs: 60000, batchMs: 5000);

    await repo.update(
      stale.copyWith(title: 'Renommée', status: SessionStatus.completed),
    );

    final SessionEntity s = (await repo.getById('s1'))!;
    expect(s.title, 'Renommée');
    expect(s.status, SessionStatus.completed);
    expect(s.cloudRealtimeMs, 60000);
    expect(s.cloudBatchMs, 5000);
  });

  test('ajout à une note supprimée : rien, pas d erreur', () async {
    await repo.delete('s1');
    await repo.addCloudUsage('s1', realtimeMs: 1000);
    expect(await repo.getById('s1'), isNull);
  });
}
