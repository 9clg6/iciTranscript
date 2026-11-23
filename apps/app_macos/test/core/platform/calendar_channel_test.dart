import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/core/platform/calendar_channel.dart';

import '../../helpers/calendar_fakes.dart';

// Côté Dart de l'agenda macOS (T5, besoins 1 à 3, 8). Le contrat du canal
// `com.icitranscript/calendar` est décrit dans test/helpers/calendar_fakes.dart.
//
// API supposée :
// - lib/application/services/calendar/calendar_event.dart :
//   `enum CalendarAccess { notDetermined, granted, denied }` ;
//   `class CalendarInfo` (const) {id, title} ;
//   `class CalendarEvent` (voir calendar_rules_test.dart).
// - lib/core/platform/calendar_channel.dart : `class CalendarChannel`
//   (`const CalendarChannel()`), `Future<CalendarAccess> accessStatus()`,
//   `Future<CalendarAccess> requestAccess()`,
//   `Future<List<CalendarInfo>> calendars()`,
//   `Future<List<CalendarEvent>> events({required DateTime from,
//   required DateTime to, List<String>? calendarIds})`,
//   `Future<void> openPrivacySettings()`, `Stream<void> get changes`.
// - lib/core/providers/platform/calendar_channel.provider.dart :
//   `calendarChannelProvider` (keepAlive).
//
// Statuts : seul `fullAccess` permet de lire ; `writeOnly`, `restricted`,
// `denied` et toute valeur inconnue = refusé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const CalendarChannel channel = CalendarChannel();

  group('statut d\'accès', () {
    const Map<String, CalendarAccess> mapping = <String, CalendarAccess>{
      'notDetermined': CalendarAccess.notDetermined,
      'fullAccess': CalendarAccess.granted,
      'writeOnly': CalendarAccess.denied,
      'denied': CalendarAccess.denied,
      'restricted': CalendarAccess.denied,
      'quelqueChoseDeNouveau': CalendarAccess.denied,
    };
    mapping.forEach((String raw, CalendarAccess expected) {
      test('accessStatus « $raw » → $expected', () async {
        FakeCalendarPlatform(status: raw).install();

        expect(await channel.accessStatus(), expected);
      });
    });

    test('requestAccess rend le statut après l\'invite système', () async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        afterRequest: 'denied',
      )..install();

      expect(await channel.requestAccess(), CalendarAccess.denied);
      expect(platform.callsTo('requestAccess'), hasLength(1));
    });
  });

  test('calendars rend id et titre de chaque agenda', () async {
    FakeCalendarPlatform().install();

    final List<CalendarInfo> list = await channel.calendars();

    expect(list.map((CalendarInfo c) => (c.id, c.title)), <(String, String)>[
      ('work', 'Travail'),
      ('home', 'Perso'),
    ]);
  });

  group('events', () {
    final DateTime from = DateTime(2026, 11, 23);
    final DateTime to = DateTime(2026, 11, 25);

    test('envoie la plage en ms epoch et les agendas choisis', () async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform()..install();

      await channel.events(from: from, to: to, calendarIds: <String>['work']);

      final MethodCall call = platform.callsTo('events').single;
      expect(call.arguments, <String, Object?>{
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'calendarIds': <String>['work'],
      });
    });

    test('sans choix d\'agendas : calendarIds null (= tous)', () async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform()..install();

      await channel.events(from: from, to: to);

      expect(
        (platform.callsTo('events').single.arguments as Map<Object?, Object?>)
            .containsKey('calendarIds'),
        isTrue,
      );
      expect(
        (platform.callsTo('events').single.arguments
            as Map<Object?, Object?>)['calendarIds'],
        isNull,
      );
    });

    test('lit chaque champ de l\'événement', () async {
      final DateTime start = DateTime(2026, 11, 23, 10, 30);
      final DateTime end = DateTime(2026, 11, 23, 11, 15);
      FakeCalendarPlatform(
        events: <Map<String, Object?>>[
          eventJson(
            id: 'evt-1@1763890200000',
            title: 'Comité produit',
            start: start,
            end: end,
            declined: true,
            calendarId: 'work',
            calendarTitle: 'Travail',
            attendees: <String>['Alice Martin', 'Chloé Durand'],
          ),
        ],
      ).install();

      final CalendarEvent e = (await channel.events(from: from, to: to)).single;

      expect(e.id, 'evt-1@1763890200000');
      expect(e.title, 'Comité produit');
      expect(e.start, start);
      expect(e.end, end);
      expect(e.allDay, isFalse);
      expect(e.declined, isTrue);
      expect(e.calendarId, 'work');
      expect(e.calendarTitle, 'Travail');
      expect(e.attendeeNames, <String>['Alice Martin', 'Chloé Durand']);
      expect(e.attendeeCount, 2);
    });

    test('participants : noms seulement, jamais d\'adresse e-mail, '
        'mais chacun compte', () async {
      FakeCalendarPlatform(
        events: <Map<String, Object?>>[
          eventJson(
            id: 'e',
            title: 'Point',
            start: DateTime(2026, 11, 23, 10),
            end: DateTime(2026, 11, 23, 11),
            attendees: <String>[
              'Alice Martin',
              'bob@example.com',
              'mailto:carol@example.org',
              '  ',
              'Chloé Durand',
            ],
          ),
        ],
      ).install();

      final CalendarEvent e = (await channel.events(from: from, to: to)).single;

      expect(e.attendeeNames, <String>['Alice Martin', 'Chloé Durand']);
      expect(e.attendeeCount, 5);
    });

    test('journée entière lue comme telle', () async {
      FakeCalendarPlatform(
        events: <Map<String, Object?>>[
          eventJson(
            id: 'conge',
            title: 'Congé',
            start: DateTime(2026, 11, 23),
            end: DateTime(2026, 11, 24),
            allDay: true,
          ),
        ],
      ).install();

      expect((await channel.events(from: from, to: to)).single.allDay, isTrue);
    });

    test(
      'champs facultatifs absents : valeurs neutres, pas d\'erreur',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(kCalendarChannel), (
              MethodCall call,
            ) async {
              return <Object?>[
                <String, Object?>{
                  'id': 'e',
                  'title': 'Sans détails',
                  'start': DateTime(2026, 11, 23, 10).millisecondsSinceEpoch,
                  'end': DateTime(2026, 11, 23, 11).millisecondsSinceEpoch,
                },
              ];
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel(kCalendarChannel),
                null,
              ),
        );

        final CalendarEvent e = (await channel.events(
          from: from,
          to: to,
        )).single;

        expect(e.allDay, isFalse);
        expect(e.declined, isFalse);
        expect(e.attendeeNames, isEmpty);
        expect(e.attendeeCount, 0);
      },
    );
  });

  test('openPrivacySettings appelle Swift', () async {
    final FakeCalendarPlatform platform = FakeCalendarPlatform()..install();

    await channel.openPrivacySettings();

    expect(platform.callsTo('openPrivacySettings'), hasLength(1));
  });

  test('« changed » venu de Swift émet sur changes', () async {
    final FakeCalendarPlatform platform = FakeCalendarPlatform()..install();
    int changes = 0;
    final StreamSubscription<void> sub = channel.changes.listen(
      (_) => changes++,
    );
    addTearDown(sub.cancel);

    await platform.notifyChanged();
    await Future<void>.delayed(Duration.zero);

    expect(changes, 1);
  });
}
