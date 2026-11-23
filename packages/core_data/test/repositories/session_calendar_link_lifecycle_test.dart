import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/datasources/local/impl/transcript.local.data_source.impl.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_data/repositories/transcript.repository.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/params/stop_session.param.dart';
import 'package:core_domain/domain/params/update_session_title.param.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:core_domain/domain/usecases/update_session_title.use_case.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

// T5, besoin 3 (revue PR #22) : une note liée garde son lien (id de
// l'événement, titre de l'événement, noms des participants) à travers les
// chemins qui réécrivent la session : Arrêter, Renommer, et la réparation au
// lancement qui la marque `interrupted`. Vrais data source, mappers et
// dépôts sur une base Drift en mémoire : `SessionLocalDataSourceImpl.update`
// écrit les trois colonnes à chaque mise à jour, un chemin qui
// reconstruirait la session sans elles effacerait le lien.
void main() {
  late AppDatabase db;
  late SessionRepositoryImpl sessions;
  late TranscriptRepositoryImpl transcripts;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sessions = SessionRepositoryImpl(
      sessionLocalDataSource: SessionLocalDataSourceImpl(
        sessionDao: SessionDao(db),
      ),
    );
    transcripts = TranscriptRepositoryImpl(
      transcriptLocalDataSource: TranscriptLocalDataSourceImpl(
        transcriptSegmentDao: TranscriptSegmentDao(db),
      ),
    );
  });
  tearDown(() => db.close());

  const SessionCalendarLink link = SessionCalendarLink(
    eventId: 'evt-42',
    eventTitle: 'Comité produit',
    attendees: <String>['Alice Martin', 'Chloé Durand'],
  );

  Future<String> startLinked() async {
    final SessionEntity s = (await StartSessionUseCase(
      sessionRepository: sessions,
    ).executeLinked(link)).data!;
    return s.id;
  }

  Future<SessionEntity> reread(String id) async =>
      (await sessions.getById(id))!;

  void expectLinked(SessionEntity s) {
    expect(s.calendarEventId, 'evt-42');
    expect(s.calendarEventTitle, 'Comité produit');
    expect(s.attendees, <String>['Alice Martin', 'Chloé Durand']);
  }

  test('après Arrêter : session close, lien intact', () async {
    final String id = await startLinked();

    await StopSessionUseCase(
      sessionRepository: sessions,
    ).invoke(StopSessionParam(sessionId: id));

    final SessionEntity s = await reread(id);
    expect(s.status, SessionStatus.completed);
    expect(s.title, 'Comité produit');
    expectLinked(s);
  });

  test('après Renommer : nouveau titre, lien intact', () async {
    final String id = await startLinked();

    await UpdateSessionTitleUseCase(
      sessionRepository: sessions,
    ).invoke(UpdateSessionTitleParam(sessionId: id, newTitle: 'Comité Q4'));

    final SessionEntity s = await reread(id);
    expect(s.title, 'Comité Q4');
    expectLinked(s);
  });

  test(
    'après la réparation au lancement (interrupted) : lien intact',
    () async {
      final String id = await startLinked();

      await RepairInterruptedSessionsUseCase(
        sessionRepository: sessions,
        transcriptRepository: transcripts,
      ).invoke();

      final SessionEntity s = await reread(id);
      expect(s.status, SessionStatus.interrupted);
      expectLinked(s);
    },
  );

  test('Arrêter puis Renommer : lien intact au bout de la chaîne', () async {
    final String id = await startLinked();
    await StopSessionUseCase(
      sessionRepository: sessions,
    ).invoke(StopSessionParam(sessionId: id));

    await UpdateSessionTitleUseCase(
      sessionRepository: sessions,
    ).invoke(UpdateSessionTitleParam(sessionId: id, newTitle: 'Comité Q4'));

    expectLinked(await reread(id));
  });
}
