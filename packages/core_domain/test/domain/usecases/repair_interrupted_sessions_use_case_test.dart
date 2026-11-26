import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:test/test.dart';

/// Besoin T1.3 : au lancement, une session restée `active` après un crash
/// est close, avec une durée tirée de son dernier segment.
///
/// Dépôts en mémoire (et non mockito) : le test lit l'état final, pas la
/// suite des appels.
void main() {
  late _InMemorySessionRepository sessions;
  late _InMemoryTranscriptRepository segments;
  late RepairInterruptedSessionsUseCase useCase;

  final DateTime start = DateTime(2026, 11, 21, 14);

  SessionEntity session(
    String id,
    SessionStatus status, {
    int? durationSeconds,
  }) => SessionEntity(
    id: id,
    title: 'Réunion $id',
    createdAt: start,
    updatedAt: start,
    durationSeconds: durationSeconds,
    status: status,
  );

  TranscriptSegmentEntity segment(String sessionId, int timestampMs) =>
      TranscriptSegmentEntity(
        id: '$sessionId-$timestampMs',
        sessionId: sessionId,
        source: AudioSource.input,
        text: 'phrase',
        timestampMs: timestampMs,
        createdAt: start.add(Duration(milliseconds: timestampMs)),
      );

  setUp(() {
    sessions = _InMemorySessionRepository();
    segments = _InMemoryTranscriptRepository();
    useCase = RepairInterruptedSessionsUseCase(
      sessionRepository: sessions,
      transcriptRepository: segments,
    );
  });

  test(
    'ferme une session restée active, durée prise sur son dernier segment',
    () async {
      sessions.store['crashed'] = session('crashed', SessionStatus.active);
      for (final int ts in <int>[120000, 3723000, 60000]) {
        await segments.save(segment('crashed', ts));
      }

      await useCase.invoke();

      final SessionEntity repaired = sessions.store['crashed']!;
      expect(repaired.status, isNot(SessionStatus.active));
      expect(repaired.status, isNot(SessionStatus.error));
      expect(repaired.durationSeconds, 3723);
    },
  );

  test('ferme une session active sans segment avec une durée nulle', () async {
    sessions.store['empty'] = session('empty', SessionStatus.active);

    await useCase.invoke();

    expect(sessions.store['empty']!.status, isNot(SessionStatus.active));
    expect(sessions.store['empty']!.durationSeconds, 0);
  });

  test('ne touche pas aux sessions déjà closes', () async {
    final SessionEntity done = session(
      'done',
      SessionStatus.completed,
      durationSeconds: 1800,
    );
    final SessionEntity failed = session('failed', SessionStatus.error);
    sessions.store
      ..['done'] = done
      ..['failed'] = failed;
    await segments.save(segment('done', 5000));

    await useCase.invoke();

    expect(sessions.store['done'], done);
    expect(sessions.store['failed'], failed);
  });

  test('garde les segments de la session réparée', () async {
    sessions.store['crashed'] = session('crashed', SessionStatus.active);
    await segments.save(segment('crashed', 1000));
    await segments.save(segment('crashed', 2000));

    await useCase.invoke();

    expect(await segments.getBySessionId('crashed'), hasLength(2));
  });
}

final class _InMemorySessionRepository implements SessionRepository {
  final Map<String, SessionEntity> store = <String, SessionEntity>{};

  @override
  Future<List<SessionEntity>> getAll() async => store.values.toList();

  @override
  Future<SessionEntity?> getById(String id) async => store[id];

  @override
  Future<SessionEntity> create(SessionEntity session) async =>
      store[session.id] = session;

  @override
  Future<SessionEntity> update(SessionEntity session) async =>
      store[session.id] = session;

  @override
  Future<void> delete(String id) async => store.remove(id);

  @override
  Stream<List<SessionEntity>> watchAll() =>
      Stream<List<SessionEntity>>.value(store.values.toList());

  @override
  Future<void> addCloudUsage(
    String sessionId, {
    int realtimeMs = 0,
    int batchMs = 0,
  }) async {}
}

final class _InMemoryTranscriptRepository implements TranscriptRepository {
  final Map<String, TranscriptSegmentEntity> store =
      <String, TranscriptSegmentEntity>{};

  @override
  Future<List<TranscriptSegmentEntity>> getBySessionId(
    String sessionId,
  ) async => store.values
      .where((TranscriptSegmentEntity s) => s.sessionId == sessionId)
      .toList();

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async =>
      store[segment.id] = segment;

  @override
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> segments,
  ) async {
    for (final TranscriptSegmentEntity s in segments) {
      store[s.id] = s;
    }
    return segments;
  }

  @override
  Future<void> deleteById(String id) async => store.remove(id);

  @override
  Future<void> deleteBySessionId(String sessionId) async =>
      store.removeWhere(
        (String _, TranscriptSegmentEntity s) => s.sessionId == sessionId,
      );
}
