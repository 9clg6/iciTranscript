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

/// Tour 6, point 2 : un segment dont le texte est connu incomplet (phrase
/// en cours sauvée, ou scellée par une coupure / un arrêt brutal) le dit
/// en base, et le garde au relancement : le rattrapage remplace ces
/// segments abîmés au lieu de les laisser à côté du texte retrouvé.
///
/// API supposée : `TranscriptSegmentEntity.isPartial` (`@Default(false)`),
/// persisté (colonne en base, migration Drift).
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

  TranscriptSegmentEntity segment(String id, {required bool partial}) =>
      TranscriptSegmentEntity(
        id: id,
        sessionId: 'session-1',
        source: AudioSource.input,
        text: 'La boulangère a',
        timestampMs: 40000,
        createdAt: DateTime(2026, 11, 22, 10, 0, 40),
        isPartial: partial,
      );

  test('un segment partiel le reste une fois relu', () async {
    await repository.save(segment('p', partial: true));

    final TranscriptSegmentEntity read = (await repository.getBySessionId(
      'session-1',
    )).single;
    expect(read.isPartial, isTrue);
  });

  test('la phrase finale, même id, n est plus partielle', () async {
    await repository.save(segment('p', partial: true));
    await repository.save(segment('p', partial: false));

    final TranscriptSegmentEntity read = (await repository.getBySessionId(
      'session-1',
    )).single;
    expect(read.isPartial, isFalse);
  });

  test('par défaut, un segment est complet', () {
    expect(
      TranscriptSegmentEntity(
        id: 'x',
        sessionId: 'session-1',
        source: AudioSource.input,
        text: 'Bonjour.',
        timestampMs: 0,
        createdAt: DateTime(2026),
      ).isPartial,
      isFalse,
    );
  });
}
