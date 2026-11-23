import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/calendar/calendar_rules.dart';

// T5, besoins 2 et 3 : quels événements le bloc « À venir » montre, et à
// quel événement une note qui démarre se lie. Fonctions pures.
//
// API supposée :
// - lib/application/services/calendar/calendar_event.dart :
//   `class CalendarEvent` (const) {id, title, start, end, allDay = false,
//   declined = false, calendarId = '', calendarTitle = '',
//   attendeeNames = const <String>[], attendeeCount = 0} ;
//   `declined` = l'utilisateur a refusé l'invitation.
// - lib/application/services/calendar/calendar_rules.dart :
//   `const Duration kLinkLeadTime = Duration(minutes: 5)` ;
//   `const Duration kLinkLateStart = Duration(minutes: 15)` ;
//   `List<CalendarEvent> upcomingEvents(List<CalendarEvent> events,
//   DateTime now)` : aujourd'hui et demain, pas encore finis, sans journée
//   entière ni refusés, triés par début ;
//   `bool isInProgress(CalendarEvent e, DateTime now)` : start <= now < end ;
//   `CalendarEvent? eventToLink(List<CalendarEvent> events,
//   DateTime startedAt)`.
final DateTime _now = DateTime(2026, 11, 23, 10);

CalendarEvent _ev(
  String id, {
  required DateTime start,
  Duration length = const Duration(minutes: 30),
  bool allDay = false,
  bool declined = false,
}) => CalendarEvent(
  id: id,
  title: 'Réunion $id',
  start: start,
  end: start.add(length),
  allDay: allDay,
  declined: declined,
  calendarId: 'work',
  calendarTitle: 'Travail',
  attendeeNames: const <String>['Alice Martin', 'Chloé Durand'],
  attendeeCount: 3,
);

List<String> _ids(List<CalendarEvent> events) =>
    events.map((CalendarEvent e) => e.id).toList();

void main() {
  group('upcomingEvents', () {
    test(
      "garde les événements d'aujourd'hui et de demain, triés par début",
      () {
        final List<CalendarEvent> events = <CalendarEvent>[
          _ev('demain', start: DateTime(2026, 11, 24, 9)),
          _ev('tantot', start: DateTime(2026, 11, 23, 15)),
          _ev('bientot', start: DateTime(2026, 11, 23, 11)),
        ];

        expect(_ids(upcomingEvents(events, _now)), <String>[
          'bientot',
          'tantot',
          'demain',
        ]);
      },
    );

    test('écarte après-demain et la veille', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('apres-demain', start: DateTime(2026, 11, 25, 9)),
        _ev('hier', start: DateTime(2026, 11, 22, 9)),
        _ev('demain-soir', start: DateTime(2026, 11, 24, 23)),
      ];

      expect(_ids(upcomingEvents(events, _now)), <String>['demain-soir']);
    });

    test('écarte un événement déjà fini, garde celui en cours', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('fini', start: DateTime(2026, 11, 23, 9)),
        _ev(
          'en-cours',
          start: DateTime(2026, 11, 23, 9, 45),
          length: const Duration(minutes: 30),
        ),
      ];

      expect(_ids(upcomingEvents(events, _now)), <String>['en-cours']);
    });

    test("un événement qui finit à l'instant n'est plus à venir", () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev(
          'pile',
          start: DateTime(2026, 11, 23, 9, 30),
          length: const Duration(minutes: 30),
        ),
      ];

      expect(upcomingEvents(events, _now), isEmpty);
    });

    test('écarte les journées entières', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev(
          'conge',
          start: DateTime(2026, 11, 23),
          length: const Duration(days: 1),
          allDay: true,
        ),
        _ev('point', start: DateTime(2026, 11, 23, 11)),
      ];

      expect(_ids(upcomingEvents(events, _now)), <String>['point']);
    });

    test("écarte les invitations refusées par l'utilisateur", () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('refuse', start: DateTime(2026, 11, 23, 11), declined: true),
        _ev('accepte', start: DateTime(2026, 11, 23, 12)),
      ];

      expect(_ids(upcomingEvents(events, _now)), <String>['accepte']);
    });

    test('liste vide : rien à venir', () {
      expect(upcomingEvents(const <CalendarEvent>[], _now), isEmpty);
    });
  });

  group('isInProgress', () {
    final CalendarEvent e = _ev('e', start: DateTime(2026, 11, 23, 10));

    test('au début : en cours', () => expect(isInProgress(e, e.start), isTrue));
    test(
      'une seconde avant : pas en cours',
      () => expect(
        isInProgress(e, e.start.subtract(const Duration(seconds: 1))),
        isFalse,
      ),
    );
    test(
      'à la fin : plus en cours',
      () => expect(isInProgress(e, e.end), isFalse),
    );
  });

  group('eventToLink', () {
    test('un événement en cours est lié', () {
      final CalendarEvent e = _ev(
        'long',
        start: DateTime(2026, 11, 23, 8),
        length: const Duration(hours: 3),
      );

      expect(eventToLink(<CalendarEvent>[e], _now)?.id, 'long');
    });

    test('un événement qui commence dans 5 minutes pile est lié', () {
      final CalendarEvent e = _ev('proche', start: _now.add(kLinkLeadTime));

      expect(kLinkLeadTime, const Duration(minutes: 5));
      expect(eventToLink(<CalendarEvent>[e], _now)?.id, 'proche');
    });

    test('un événement qui commence dans 5 min 1 s n\'est pas lié', () {
      final CalendarEvent e = _ev(
        'loin',
        start: _now.add(const Duration(minutes: 5, seconds: 1)),
      );

      expect(eventToLink(<CalendarEvent>[e], _now), isNull);
    });

    test('un enregistrement lancé 15 minutes après le début est lié', () {
      final CalendarEvent e = _ev(
        'retard',
        start: _now.subtract(kLinkLateStart),
        length: const Duration(hours: 1),
      );

      expect(kLinkLateStart, const Duration(minutes: 15));
      expect(eventToLink(<CalendarEvent>[e], _now)?.id, 'retard');
    });

    test('jamais un événement fini, même commencé il y a moins de 15 min', () {
      final CalendarEvent e = _ev(
        'court',
        start: _now.subtract(const Duration(minutes: 10)),
        length: const Duration(minutes: 5),
      );

      expect(eventToLink(<CalendarEvent>[e], _now), isNull);
    });

    test('rien à proximité : pas de lien', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('matin', start: DateTime(2026, 11, 23, 8)),
        _ev('midi', start: DateTime(2026, 11, 23, 12)),
      ];

      expect(eventToLink(events, _now), isNull);
    });

    test('réunions à la suite : la plus proche du début gagne', () {
      // 9:30–10:00 se termine à 10:00 pile (fini) ; 10:02 commence bientôt ;
      // 9:00–11:00 est en cours mais a commencé il y a une heure.
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('precedente', start: DateTime(2026, 11, 23, 9, 30)),
        _ev(
          'atelier',
          start: DateTime(2026, 11, 23, 9),
          length: const Duration(hours: 2),
        ),
        _ev('suivante', start: DateTime(2026, 11, 23, 10, 2)),
      ];

      expect(eventToLink(events, _now)?.id, 'suivante');
    });

    test(
      'en cours depuis 3 min contre début dans 4 min : la plus proche gagne',
      () {
        final List<CalendarEvent> events = <CalendarEvent>[
          _ev('dans4', start: _now.add(const Duration(minutes: 4))),
          _ev('depuis3', start: _now.subtract(const Duration(minutes: 3))),
        ];

        expect(eventToLink(events, _now)?.id, 'depuis3');
      },
    );

    test('ni journée entière ni invitation refusée', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev(
          'conge',
          start: DateTime(2026, 11, 23),
          length: const Duration(days: 1),
          allDay: true,
        ),
        _ev('refuse', start: _now, declined: true),
      ];

      expect(eventToLink(events, _now), isNull);
    });
  });
}
