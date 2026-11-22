import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// T5, besoin 3 : une note liée à un événement d'agenda garde le lien
/// (id de l'événement, titre de l'événement, noms des participants) après
/// relecture ; retirer le lien remet les trois colonnes à null.
///
/// Les colonnes existent déjà (schéma v2 : `calendar_event_id`,
/// `calendar_event_title`, `attendees` = tableau JSON de noms) ; aucune
/// nouvelle version de schéma n'est attendue pour cette tranche.
///
/// API supposée (core_domain, SessionEntity) :
/// - `String? calendarEventId`, `String? calendarEventTitle` ;
/// - `List<String> attendees` (`@Default(<String>[])`), noms seulement.
/// Mapper, SessionLocalModel et SessionLocalDataSourceImpl (getAll, getById,
/// insert, update, watchAll) les transportent ; liste vide ou lien retiré =
/// colonne `attendees` à null.
void main() {
  late AppDatabase db;
  late SessionRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SessionRepositoryImpl(
      sessionLocalDataSource: SessionLocalDataSourceImpl(
        sessionDao: SessionDao(db),
      ),
    );
  });
  tearDown(() => db.close());

  final DateTime start = DateTime(2026, 11, 23, 10, 30);
  SessionEntity session({
    String? eventId,
    String? eventTitle,
    List<String> attendees = const <String>[],
  }) => SessionEntity(
    id: 's1',
    title: eventTitle ?? 'Session 2026-11-23 10:30',
    createdAt: start,
    updatedAt: start,
    status: SessionStatus.active,
    calendarEventId: eventId,
    calendarEventTitle: eventTitle,
    attendees: attendees,
  );

  Future<Session> row() =>
      (db.select(db.sessions)..where(($SessionsTable t) => t.id.equals('s1')))
          .getSingle();

  test('une note créée liée relit son événement et ses participants', () async {
    await repo.create(
      session(
        eventId: 'evt-42',
        eventTitle: 'Comité produit',
        attendees: <String>['Alice Martin', 'Chloé Durand'],
      ),
    );

    final SessionEntity read = (await repo.getById('s1'))!;
    expect(read.calendarEventId, 'evt-42');
    expect(read.calendarEventTitle, 'Comité produit');
    expect(read.attendees, <String>['Alice Martin', 'Chloé Durand']);
  });

  test('les participants sont rangés en tableau JSON de noms', () async {
    await repo.create(
      session(
        eventId: 'evt-42',
        eventTitle: 'Comité produit',
        attendees: <String>['Alice Martin', 'Chloé Durand'],
      ),
    );

    final Session r = await row();
    expect(r.calendarEventId, 'evt-42');
    expect(r.calendarEventTitle, 'Comité produit');
    expect(jsonDecode(r.attendees!), <String>['Alice Martin', 'Chloé Durand']);
  });

  test('une note sans lien relit null et une liste vide', () async {
    await repo.create(session());

    final SessionEntity read = (await repo.getById('s1'))!;
    expect(read.calendarEventId, isNull);
    expect(read.calendarEventTitle, isNull);
    expect(read.attendees, isEmpty);
    expect((await row()).attendees, isNull);
  });

  test('lier une note existante (update) range le lien', () async {
    await repo.create(session());

    await repo.update(
      session(
        eventId: 'evt-7',
        eventTitle: 'Point hebdo',
        attendees: <String>['Bérénice'],
      ),
    );

    final SessionEntity read = (await repo.getById('s1'))!;
    expect(read.calendarEventId, 'evt-7');
    expect(read.calendarEventTitle, 'Point hebdo');
    expect(read.attendees, <String>['Bérénice']);
  });

  test('retirer le lien remet les trois colonnes à null', () async {
    await repo.create(
      session(
        eventId: 'evt-42',
        eventTitle: 'Comité produit',
        attendees: <String>['Alice Martin'],
      ),
    );

    await repo.update(
      session().copyWith(title: 'Comité produit'),
    );

    final Session r = await row();
    expect(r.calendarEventId, isNull);
    expect(r.calendarEventTitle, isNull);
    expect(r.attendees, isNull);
    final SessionEntity read = (await repo.getById('s1'))!;
    expect(read.calendarEventId, isNull);
    expect(read.attendees, isEmpty);
  });

  test('getAll et watchAll transportent aussi le lien', () async {
    await repo.create(
      session(
        eventId: 'evt-42',
        eventTitle: 'Comité produit',
        attendees: <String>['Alice Martin'],
      ),
    );

    expect((await repo.getAll()).single.calendarEventId, 'evt-42');
    final List<SessionEntity> watched = await repo.watchAll().first;
    expect(watched.single.attendees, <String>['Alice Martin']);
  });

  test('une colonne attendees illisible se lit comme une liste vide', () async {
    await db.into(db.sessions).insert(
      SessionsCompanion.insert(
        id: 's1',
        title: 'Ancienne note',
        createdAt: start.toIso8601String(),
        updatedAt: start.toIso8601String(),
        status: 'completed',
        attendees: const Value<String?>('pas du json'),
      ),
    );

    expect((await repo.getById('s1'))!.attendees, isEmpty);
  });
}
