import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';

// T5, besoin 5 : quand proposer de démarrer une note. Fonction pure sur
// l'horloge, les événements d'agenda, les apps qui tiennent le micro,
// l'état d'Oats et la mémoire des suggestions déjà faites.
//
// API supposée (lib/application/services/meeting/meeting_rules.dart) :
// - constantes : `kEventSuggestLead = Duration(minutes: 1)`,
//   `kMicHoldThreshold = Duration(seconds: 3)`,
//   `kDismissSnooze = Duration(minutes: 10)`,
//   `kMinAttendeesForSuggestion = 2`,
//   `kOwnBundleId = 'fr.yellowstone-apps.ici-transcript'`,
//   `kCallApps` : `Map<String, String>` bundle id → nom affiché ;
// - `String? callAppName(String bundleId)` : nom de l'app d'appel connue,
//   par id exact ou par préfixe `<id connu>.` (processus auxiliaire, ex.
//   `com.google.Chrome.helper`) ; null sinon ;
// - `enum MeetingSource { calendar, call }` ;
// - `class MeetingSuggestion` {source, key (String, opaque), event
//   (CalendarEvent?, source calendar), appName (String?, source call),
//   bundleId (String?, source call)} ;
// - `MeetingSuggestion? meetingSuggestion({required DateTime now,
//   required List<CalendarEvent> events,
//   required Map<String, DateTime> micHolders, // bundle id → tenu depuis
//   required bool ownCaptureActive, // Oats enregistre ou dicte
//   required bool detectionEnabled,
//   Set<String> eventIdsWithNote = const <String>{},
//   Set<String> alreadySuggested = const <String>{}, // clés déjà montrées
//   DateTime? dismissedAt})` ;
// - `bool suggestionStillValid(MeetingSuggestion s, {required DateTime now,
//   required List<CalendarEvent> events,
//   required Map<String, DateTime> micHolders})`.
//
// Choix : l'agenda passe avant le micro quand les deux s'appliquent ;
// « Ignorer » met toute suggestion en sourdine 10 minutes ; journées
// entières et invitations refusées ne déclenchent rien.
final DateTime _now = DateTime(2026, 11, 23, 10);

CalendarEvent _ev(
  String id, {
  required DateTime start,
  Duration length = const Duration(minutes: 30),
  int attendees = 3,
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
  attendeeCount: attendees,
);

MeetingSuggestion? _suggest({
  DateTime? now,
  List<CalendarEvent> events = const <CalendarEvent>[],
  Map<String, DateTime> micHolders = const <String, DateTime>{},
  bool ownCaptureActive = false,
  bool detectionEnabled = true,
  Set<String> eventIdsWithNote = const <String>{},
  Set<String> alreadySuggested = const <String>{},
  DateTime? dismissedAt,
}) => meetingSuggestion(
  now: now ?? _now,
  events: events,
  micHolders: micHolders,
  ownCaptureActive: ownCaptureActive,
  detectionEnabled: detectionEnabled,
  eventIdsWithNote: eventIdsWithNote,
  alreadySuggested: alreadySuggested,
  dismissedAt: dismissedAt,
);

Map<String, DateTime> _held(String bundleId, Duration since) =>
    <String, DateTime>{bundleId: _now.subtract(since)};

void main() {
  test('constantes du besoin', () {
    expect(kEventSuggestLead, const Duration(minutes: 1));
    expect(kMicHoldThreshold, const Duration(seconds: 3));
    expect(kDismissSnooze, const Duration(minutes: 10));
    expect(kMinAttendeesForSuggestion, 2);
  });

  group('agenda', () {
    test('un événement à 2 participants qui commence dans 1 min : suggéré', () {
      final MeetingSuggestion? s = _suggest(
        events: <CalendarEvent>[
          _ev('e1', start: _now.add(kEventSuggestLead), attendees: 2),
        ],
      );

      expect(s?.source, MeetingSource.calendar);
      expect(s?.event?.id, 'e1');
    });

    test('dans 1 min 1 s : pas encore', () {
      expect(
        _suggest(
          events: <CalendarEvent>[
            _ev('e1', start: _now.add(const Duration(minutes: 1, seconds: 1))),
          ],
        ),
        isNull,
      );
    });

    test('un seul participant : rien', () {
      expect(
        _suggest(
          events: <CalendarEvent>[_ev('solo', start: _now, attendees: 1)],
        ),
        isNull,
      );
    });

    test('en cours et sans note : suggéré', () {
      final MeetingSuggestion? s = _suggest(
        events: <CalendarEvent>[
          _ev('e1', start: _now.subtract(const Duration(minutes: 20))),
        ],
      );

      expect(s?.event?.id, 'e1');
    });

    test('en cours mais une note existe déjà pour lui : rien', () {
      expect(
        _suggest(
          events: <CalendarEvent>[
            _ev('e1', start: _now.subtract(const Duration(minutes: 20))),
          ],
          eventIdsWithNote: <String>{'e1'},
        ),
        isNull,
      );
    });

    test('fini : rien', () {
      expect(
        _suggest(
          events: <CalendarEvent>[
            _ev(
              'e1',
              start: _now.subtract(const Duration(minutes: 30)),
              length: const Duration(minutes: 30),
            ),
          ],
        ),
        isNull,
      );
    });

    test('journée entière ou invitation refusée : rien', () {
      expect(
        _suggest(
          events: <CalendarEvent>[
            _ev(
              'conge',
              start: DateTime(2026, 11, 23),
              length: const Duration(days: 1),
              allDay: true,
            ),
            _ev('refus', start: _now, declined: true),
          ],
        ),
        isNull,
      );
    });

    test('jamais deux fois pour le même événement', () {
      final List<CalendarEvent> events = <CalendarEvent>[
        _ev('e1', start: _now),
      ];
      final MeetingSuggestion first = _suggest(events: events)!;

      expect(
        _suggest(
          events: events,
          now: _now.add(const Duration(minutes: 5)),
          alreadySuggested: <String>{first.key},
        ),
        isNull,
      );
    });
  });

  group('micro tenu par une app d\'appel', () {
    test(
      'Zoom tient le micro depuis 3 s : « appel » avec le nom de l\'app',
      () {
        final MeetingSuggestion? s = _suggest(
          micHolders: _held('us.zoom.xos', kMicHoldThreshold),
        );

        expect(s?.source, MeetingSource.call);
        expect(s?.appName, 'Zoom');
        expect(s?.bundleId, 'us.zoom.xos');
      },
    );

    test('depuis 2,9 s : pas encore', () {
      expect(
        _suggest(
          micHolders: _held('us.zoom.xos', const Duration(milliseconds: 2900)),
        ),
        isNull,
      );
    });

    test('un navigateur qui tient le micro (Google Meet) : suggéré', () {
      final MeetingSuggestion? s = _suggest(
        micHolders: _held('com.google.Chrome', const Duration(seconds: 5)),
      );

      expect(s?.source, MeetingSource.call);
      expect(s?.appName, isNotEmpty);
    });

    test('une app inconnue qui tient le micro : rien', () {
      expect(
        _suggest(
          micHolders: _held('com.example.recorder', const Duration(minutes: 1)),
        ),
        isNull,
      );
    });

    test('Oats lui-même ne déclenche jamais, même sans enregistrement', () {
      expect(
        _suggest(micHolders: _held(kOwnBundleId, const Duration(minutes: 1))),
        isNull,
      );
    });

    test('jamais deux fois pour la même prise de micro continue', () {
      final Map<String, DateTime> holders = _held(
        'us.zoom.xos',
        const Duration(seconds: 4),
      );
      final MeetingSuggestion first = _suggest(micHolders: holders)!;

      expect(
        _suggest(
          now: _now.add(const Duration(minutes: 1)),
          micHolders: holders,
          alreadySuggested: <String>{first.key},
        ),
        isNull,
      );
    });

    test(
      'une nouvelle prise de micro plus tard est une nouvelle suggestion',
      () {
        final MeetingSuggestion first = _suggest(
          micHolders: _held('us.zoom.xos', const Duration(seconds: 4)),
        )!;
        final DateTime later = _now.add(const Duration(minutes: 30));

        final MeetingSuggestion? again = _suggest(
          now: later,
          micHolders: <String, DateTime>{
            'us.zoom.xos': later.subtract(const Duration(seconds: 4)),
          },
          alreadySuggested: <String>{first.key},
        );

        expect(again, isNotNull);
        expect(again!.key, isNot(first.key));
      },
    );
  });

  group('callAppName', () {
    const Map<String, String> known = <String, String>{
      'us.zoom.xos': 'Zoom',
      'com.microsoft.teams2': 'Microsoft Teams',
      'com.tinyspeck.slackmacgap': 'Slack',
      'com.apple.FaceTime': 'FaceTime',
      'net.whatsapp.WhatsApp': 'WhatsApp',
      'Cisco-Systems.Spark': 'Webex',
      'com.hnc.Discord': 'Discord',
    };
    known.forEach((String id, String name) {
      test('$id → $name', () => expect(callAppName(id), name));
    });

    for (final String browser in <String>[
      'com.google.Chrome',
      'com.apple.Safari',
      'company.thebrowser.Browser',
      'org.mozilla.firefox',
      'com.microsoft.edgemac',
      'com.brave.Browser',
    ]) {
      test('navigateur $browser connu (Google Meet)', () {
        expect(callAppName(browser), isNotNull);
      });
    }

    test('processus auxiliaire d\'une app connue', () {
      expect(
        callAppName('com.google.Chrome.helper'),
        callAppName('com.google.Chrome'),
      );
    });

    test('un préfixe sans point ne compte pas', () {
      expect(callAppName('us.zoom.xosfake'), isNull);
    });

    test(
      'inconnu → null',
      () => expect(callAppName('com.example.app'), isNull),
    );
  });

  group('garde-fous', () {
    final List<CalendarEvent> events = <CalendarEvent>[_ev('e1', start: _now)];
    final Map<String, DateTime> zoom = _held(
      'us.zoom.xos',
      const Duration(seconds: 10),
    );

    test('jamais pendant qu\'Oats enregistre ou dicte', () {
      expect(
        _suggest(events: events, micHolders: zoom, ownCaptureActive: true),
        isNull,
      );
    });

    test('détection coupée : rien', () {
      expect(
        _suggest(events: events, micHolders: zoom, detectionEnabled: false),
        isNull,
      );
    });

    test('ignoré il y a 9 min 59 s : rien', () {
      expect(
        _suggest(
          micHolders: zoom,
          dismissedAt: _now.subtract(const Duration(minutes: 9, seconds: 59)),
        ),
        isNull,
      );
    });

    test('ignoré il y a 10 min : de nouveau possible', () {
      expect(
        _suggest(micHolders: zoom, dismissedAt: _now.subtract(kDismissSnooze)),
        isNotNull,
      );
    });

    test('agenda et micro à la fois : l\'événement passe avant', () {
      final MeetingSuggestion? s = _suggest(events: events, micHolders: zoom);

      expect(s?.source, MeetingSource.calendar);
      expect(s?.event?.id, 'e1');
    });
  });

  group('suggestionStillValid', () {
    test('appel : disparaît quand l\'app lâche le micro', () {
      final Map<String, DateTime> zoom = _held(
        'us.zoom.xos',
        const Duration(seconds: 5),
      );
      final MeetingSuggestion s = _suggest(micHolders: zoom)!;

      expect(
        suggestionStillValid(
          s,
          now: _now,
          events: const <CalendarEvent>[],
          micHolders: zoom,
        ),
        isTrue,
      );
      expect(
        suggestionStillValid(
          s,
          now: _now,
          events: const <CalendarEvent>[],
          micHolders: const <String, DateTime>{},
        ),
        isFalse,
      );
    });

    test('agenda : disparaît quand l\'événement est fini', () {
      final CalendarEvent e = _ev('e1', start: _now);
      final MeetingSuggestion s = _suggest(events: <CalendarEvent>[e])!;

      expect(
        suggestionStillValid(
          s,
          now: e.end.subtract(const Duration(seconds: 1)),
          events: <CalendarEvent>[e],
          micHolders: const <String, DateTime>{},
        ),
        isTrue,
      );
      expect(
        suggestionStillValid(
          s,
          now: e.end,
          events: <CalendarEvent>[e],
          micHolders: const <String, DateTime>{},
        ),
        isFalse,
      );
    });

    test('agenda : disparaît si l\'événement est supprimé de l\'agenda', () {
      final CalendarEvent e = _ev('e1', start: _now);
      final MeetingSuggestion s = _suggest(events: <CalendarEvent>[e])!;

      expect(
        suggestionStillValid(
          s,
          now: _now,
          events: const <CalendarEvent>[],
          micHolders: const <String, DateTime>{},
        ),
        isFalse,
      );
    });
  });
}
