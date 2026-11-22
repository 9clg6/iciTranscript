import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/datasources/local/impl/transcript.local.data_source.impl.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_data/repositories/transcript.repository.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Contrat du port [TranscriptRepositoryImpl] sur une vraie base SQLite
/// en mémoire.
///
/// Besoin T1.3 : la phrase en cours est sauvée comme segment provisoire,
/// puis remplacée par la phrase finale, sans doublon. Le port doit donc
/// remplacer un segment de même id, et pouvoir en retirer un (phrase finale
/// écartée, ex. hallucination).
void main() {
  late AppDatabase db;
  late TranscriptRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = TranscriptRepositoryImpl(
      transcriptLocalDataSource: TranscriptLocalDataSourceImpl(
        transcriptSegmentDao: TranscriptSegmentDao(db),
      ),
    );
    await SessionRepositoryImpl(
      sessionLocalDataSource: SessionLocalDataSourceImpl(
        sessionDao: SessionDao(db),
      ),
    ).create(
      SessionEntity(
        id: 'session-1',
        title: 'Réunion',
        createdAt: DateTime(2026, 11, 22, 10),
        updatedAt: DateTime(2026, 11, 22, 10),
        status: SessionStatus.active,
      ),
    );
  });

  tearDown(() => db.close());

  TranscriptSegmentEntity segment(String id, String text) =>
      TranscriptSegmentEntity(
        id: id,
        sessionId: 'session-1',
        source: AudioSource.input,
        text: text,
        timestampMs: 12000,
        createdAt: DateTime(2026, 11, 22, 10, 0, 12),
      );

  test('sauver un segment de même id remplace le provisoire', () async {
    await repository.save(segment('input-1', 'Bonjour à'));
    await repository.save(segment('input-1', 'Bonjour à tous.'));

    final List<TranscriptSegmentEntity> saved = await repository
        .getBySessionId('session-1');
    expect(saved, hasLength(1));
    expect(saved.single.text, 'Bonjour à tous.');
  });

  test('retirer un segment par son id laisse les autres en place', () async {
    await repository.save(segment('input-1', 'Bonjour à tous.'));
    await repository.save(segment('input-2', 'Thank you.'));

    await repository.deleteById('input-2');

    final List<TranscriptSegmentEntity> saved = await repository
        .getBySessionId('session-1');
    expect(saved.map((TranscriptSegmentEntity s) => s.id), <String>[
      'input-1',
    ]);
  });
}
