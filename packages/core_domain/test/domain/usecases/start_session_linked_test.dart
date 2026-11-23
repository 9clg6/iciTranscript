import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_foundation/interfaces/results.usecases.dart';
import 'package:test/test.dart';

// T5, besoin 3 : une note démarrée liée à un événement porte l'id de
// l'événement, son titre (qui devient le titre de la note) et les noms des
// participants ; sans lien, la note démarre comme avant. Un lien inutilisable
// n'empêche jamais l'enregistrement de démarrer.
//
// API : `StartSessionUseCase.executeLinked(SessionCalendarLink? link)` →
// `ResultState<SessionEntity>` ; `SessionCalendarLink {eventId, eventTitle,
// attendees}` (core_domain).
final class _MemoryRepo implements SessionRepository {
  final Map<String, SessionEntity> store = <String, SessionEntity>{};
  bool fail = false;

  @override
  Future<SessionEntity> create(SessionEntity s) async {
    if (fail) throw Exception('disque plein');
    return store[s.id] = s;
  }

  @override
  Future<List<SessionEntity>> getAll() async => store.values.toList();
  @override
  Future<SessionEntity?> getById(String id) async => store[id];
  @override
  Future<SessionEntity> update(SessionEntity s) async => store[s.id] = s;
  @override
  Future<void> delete(String id) async => store.remove(id);
  @override
  Stream<List<SessionEntity>> watchAll() =>
      Stream<List<SessionEntity>>.value(store.values.toList());
}

void main() {
  late _MemoryRepo repo;
  late StartSessionUseCase useCase;

  setUp(() {
    repo = _MemoryRepo();
    useCase = StartSessionUseCase(sessionRepository: repo);
  });

  test('liée : id de l\'événement, titre de l\'événement, noms des '
      'participants ; rangée active', () async {
    final ResultState<SessionEntity> r = await useCase.executeLinked(
      const SessionCalendarLink(
        eventId: 'evt-42',
        eventTitle: 'Comité produit',
        attendees: <String>['Alice Martin', 'Chloé Durand'],
      ),
    );

    expect(r.isSuccess, isTrue);
    final SessionEntity s = repo.store.values.single;
    expect(s.id, r.data!.id);
    expect(s.status, SessionStatus.active);
    expect(s.calendarEventId, 'evt-42');
    expect(s.calendarEventTitle, 'Comité produit');
    expect(s.title, 'Comité produit');
    expect(s.attendees, <String>['Alice Martin', 'Chloé Durand']);
  });

  test('sans lien : titre par défaut « Session … », aucun lien', () async {
    final ResultState<SessionEntity> r = await useCase.executeLinked(null);

    expect(r.isSuccess, isTrue);
    final SessionEntity s = repo.store.values.single;
    expect(s.title, startsWith('Session '));
    expect(s.calendarEventId, isNull);
    expect(s.calendarEventTitle, isNull);
    expect(s.attendees, isEmpty);
  });

  test('événement sans titre : la note démarre quand même, avec un titre '
      'non vide', () async {
    final ResultState<SessionEntity> r = await useCase.executeLinked(
      const SessionCalendarLink(eventId: 'evt-sans-titre', eventTitle: '  '),
    );

    expect(r.isSuccess, isTrue);
    final SessionEntity s = repo.store.values.single;
    expect(s.title.trim(), isNotEmpty);
    expect(s.calendarEventId, 'evt-sans-titre');
  });

  test('échec du dépôt : un échec rendu, pas une exception levée', () async {
    repo.fail = true;

    final ResultState<SessionEntity> r = await useCase.executeLinked(
      const SessionCalendarLink(eventId: 'e', eventTitle: 'Point'),
    );

    expect(r.isFailure, isTrue);
  });
}
