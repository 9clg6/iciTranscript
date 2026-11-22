import 'dart:async';
import 'dart:convert';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoins 1, 2 et 4, vus depuis l'accueil (bloc « À venir ») : connexion
// explicite, refus avec la marche à suivre, événements d'aujourd'hui et de
// demain, « En cours » avec un moyen de démarrer la note, rafraîchissement
// sur changement de l'agenda et au changement de jour, erreur avec
// Réessayer, chargement, vide. L'historique reste la liste des notes.
//
// Repères supposés (textes de fr.json, voir calendar_translations_test) :
// - bouton « Connecter l'agenda » : texte `home.upcoming.connect` ;
// - refus : texte `home.upcoming.denied`, bouton `home.upcoming.open_settings`
//   (→ méthode `openPrivacySettings` du canal) ;
// - ligne d'événement : titre, « HH:mm–HH:mm » (tiret demi-cadratin),
//   `home.upcoming.attendees` (pluriel), nom de l'agenda ; « Demain »
//   (`common.label.tomorrow`) pour un événement de demain ;
// - en cours : texte `home.upcoming.in_progress` et bouton
//   `home.upcoming.start_note` sur la ligne ;
// - vide : `home.upcoming.empty` ; erreur : `home.upcoming.error` +
//   `common.action.retry`.
// Horloge : `nowProvider` (voir start_note_link_test.dart).
final DateTime _anchor = DateTime(2026, 11, 23, 10);

void _writePrefs(Map<String, Object?> prefs) {
  prefsFile.parent.createSync(recursive: true);
  prefsFile.writeAsStringSync(jsonEncode(prefs));
}

Map<String, Object?> _event(
  String id,
  String title,
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  List<String> attendees = const <String>['Alice', 'Bruno', 'Chloé'],
  String calendarId = 'work',
  String calendarTitle = 'Travail',
  bool allDay = false,
  bool declined = false,
}) => eventJson(
  id: id,
  title: title,
  start: start,
  end: start.add(length),
  attendees: attendees,
  calendarId: calendarId,
  calendarTitle: calendarTitle,
  allDay: allDay,
  declined: declined,
);

void main() {
  setUp(resetPrefs);

  late FakeLiveTranscriptionViewModel live;

  Future<void> pumpHome(
    WidgetTester tester, {
    DateTime? now,
    List<SessionEntity> sessions = const <SessionEntity>[],
  }) async {
    live = FakeLiveTranscriptionViewModel();
    await pumpLocalized(
      tester,
      const HomeScreen(),
      settle: false,
      overrides: <Override>[
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(sessions),
        ),
        liveTranscriptionViewModelProvider.overrideWith(() => live),
        nowProvider.overrideWithValue(widgetClock(tester, now ?? _anchor)),
      ],
    );
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await settle(tester);
  }

  group('connexion', () {
    testWidgets('jamais connecté : bouton « Connecter », rien lu, '
        'même si macOS a déjà donné l\'accès', (WidgetTester tester) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[
          _event('e1', 'Comité produit', _anchor.add(const Duration(hours: 1))),
        ],
      )..install();

      await pumpHome(tester);

      expect(find.text('home.upcoming.connect'.tr()), findsOneWidget);
      expect(find.text('Comité produit'), findsNothing);
      expect(platform.dataReads, isEmpty);
    });

    testWidgets('« Connecter » accordé : demande l\'accès une fois, liste '
        'les événements et retient le choix', (WidgetTester tester) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        events: <Map<String, Object?>>[
          _event('e1', 'Comité produit', _anchor.add(const Duration(hours: 1))),
        ],
      )..install();
      await pumpHome(tester);

      await tapText(tester, 'home.upcoming.connect'.tr());

      expect(platform.callsTo('requestAccess'), hasLength(1));
      expect(find.text('Comité produit'), findsOneWidget);
      expect(find.text('home.upcoming.connect'.tr()), findsNothing);
      expect(readPrefs()['calendar_connected'], isTrue);
    });

    testWidgets('choix retenu : au lancement suivant, les événements '
        's\'affichent sans redemander', (WidgetTester tester) async {
      _writePrefs(<String, Object?>{'calendar_connected': true});
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[
          _event('e1', 'Comité produit', _anchor.add(const Duration(hours: 1))),
        ],
      )..install();

      await pumpHome(tester);

      expect(find.text('Comité produit'), findsOneWidget);
      expect(platform.callsTo('requestAccess'), isEmpty);
    });

    testWidgets('« Connecter » refusé : dit comment l\'autoriser dans '
        'Réglages Système et ouvre la bonne page', (WidgetTester tester) async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        afterRequest: 'denied',
      )..install();
      await pumpHome(tester);

      await tapText(tester, 'home.upcoming.connect'.tr());

      expect(find.textContaining('home.upcoming.denied'.tr()), findsOneWidget);
      await tapText(tester, 'home.upcoming.open_settings'.tr());
      expect(platform.callsTo('openPrivacySettings'), hasLength(1));
      expect(platform.callsTo('events'), isEmpty);
    });

    testWidgets('connecté puis accès retiré dans Réglages Système : '
        'la marche à suivre, aucun événement lu', (WidgetTester tester) async {
      _writePrefs(<String, Object?>{'calendar_connected': true});
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'denied',
      )..install();

      await pumpHome(tester);

      expect(find.textContaining('home.upcoming.denied'.tr()), findsOneWidget);
      expect(platform.callsTo('events'), isEmpty);
    });
  });

  group('événements', () {
    Future<FakeCalendarPlatform> connected(
      WidgetTester tester,
      List<Map<String, Object?>> events, {
      DateTime? now,
      Map<String, Object?> prefs = const <String, Object?>{},
    }) async {
      _writePrefs(<String, Object?>{'calendar_connected': true, ...prefs});
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
        events: events,
      )..install();
      await pumpHome(tester, now: now);
      return platform;
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text).first).dy;

    testWidgets('titre, heure de début et de fin, participants, agenda', (
      WidgetTester tester,
    ) async {
      await connected(tester, <Map<String, Object?>>[
        _event(
          'e1',
          'Comité produit',
          DateTime(2026, 11, 23, 10, 30),
          calendarTitle: 'Travail',
        ),
      ]);

      expect(find.text('Comité produit'), findsOneWidget);
      expect(find.textContaining('10:30–11:00'), findsOneWidget);
      expect(
        find.textContaining('home.upcoming.attendees'.plural(3)),
        findsOneWidget,
      );
      expect(find.textContaining('Travail'), findsOneWidget);
    });

    testWidgets('aujourd\'hui puis demain, triés par début ; demain est dit', (
      WidgetTester tester,
    ) async {
      await connected(tester, <Map<String, Object?>>[
        _event('d', 'Revue demain', DateTime(2026, 11, 24, 9)),
        _event('b', 'Point de 15 h', DateTime(2026, 11, 23, 15)),
        _event('a', 'Point de 11 h', DateTime(2026, 11, 23, 11)),
        _event('x', 'Après-demain', DateTime(2026, 11, 25, 9)),
      ]);

      expect(
        top(tester, 'Point de 11 h'),
        lessThan(top(tester, 'Point de 15 h')),
      );
      expect(
        top(tester, 'Point de 15 h'),
        lessThan(top(tester, 'Revue demain')),
      );
      expect(find.text('Après-demain'), findsNothing);
      expect(find.textContaining('common.label.tomorrow'.tr()), findsWidgets);
    });

    testWidgets(
      'ni journée entière, ni invitation refusée, ni événement fini',
      (WidgetTester tester) async {
        await connected(tester, <Map<String, Object?>>[
          _event(
            'c',
            'Congé',
            DateTime(2026, 11, 23),
            length: const Duration(days: 1),
            allDay: true,
          ),
          _event('r', 'Refusée', DateTime(2026, 11, 23, 11), declined: true),
          _event('f', 'Finie', DateTime(2026, 11, 23, 8)),
          _event('ok', 'Gardée', DateTime(2026, 11, 23, 11)),
        ]);

        expect(find.text('Gardée'), findsOneWidget);
        expect(find.text('Congé'), findsNothing);
        expect(find.text('Refusée'), findsNothing);
        expect(find.text('Finie'), findsNothing);
      },
    );

    testWidgets('seuls les agendas choisis dans Réglages sont lus', (
      WidgetTester tester,
    ) async {
      final FakeCalendarPlatform platform = await connected(
        tester,
        <Map<String, Object?>>[
          _event('w', 'Travail 11 h', DateTime(2026, 11, 23, 11)),
          _event(
            'h',
            'Dentiste',
            DateTime(2026, 11, 23, 12),
            calendarId: 'home',
            calendarTitle: 'Perso',
          ),
        ],
        prefs: <String, Object?>{
          'calendar_ids': <String>['home'],
        },
      );

      expect(find.text('Dentiste'), findsOneWidget);
      expect(find.text('Travail 11 h'), findsNothing);
      expect(
        (platform.callsTo('events').last.arguments
            as Map<Object?, Object?>)['calendarIds'],
        <String>['home'],
      );
    });

    testWidgets('en cours : « En cours » et « Démarrer la note » qui lance '
        'l\'enregistrement', (WidgetTester tester) async {
      await connected(tester, <Map<String, Object?>>[
        _event(
          'now',
          'Atelier en cours',
          _anchor.subtract(const Duration(minutes: 10)),
          length: const Duration(hours: 1),
        ),
        _event('later', 'Plus tard', DateTime(2026, 11, 23, 15)),
      ]);

      expect(find.text('home.upcoming.in_progress'.tr()), findsOneWidget);
      expect(find.text('home.upcoming.start_note'.tr()), findsOneWidget);

      await tapText(tester, 'home.upcoming.start_note'.tr());

      expect(live.startCalls, 1);
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      expect(c.read(shellViewControllerProvider), ShellView.live);
    });

    testWidgets('« Démarrer la note » pendant un enregistrement : revient '
        'au direct sans en lancer un second', (WidgetTester tester) async {
      await connected(tester, <Map<String, Object?>>[
        _event(
          'now',
          'Atelier en cours',
          _anchor.subtract(const Duration(minutes: 10)),
          length: const Duration(hours: 1),
        ),
      ]);
      await live.startSession();
      await settle(tester);

      await tapText(tester, 'home.upcoming.start_note'.tr());

      expect(live.startCalls, 1);
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      expect(c.read(shellViewControllerProvider), ShellView.live);
    });

    testWidgets('l\'agenda change (événement ajouté) : la liste suit', (
      WidgetTester tester,
    ) async {
      final FakeCalendarPlatform platform = await connected(
        tester,
        <Map<String, Object?>>[
          _event('a', 'Point de 11 h', DateTime(2026, 11, 23, 11)),
        ],
      );

      platform.events.add(_event('n', 'Nouveau', DateTime(2026, 11, 23, 16)));
      await platform.notifyChanged();
      await settle(tester);

      expect(find.text('Nouveau'), findsOneWidget);
    });

    testWidgets('au changement de jour, demain devient aujourd\'hui et '
        'après-demain apparaît', (WidgetTester tester) async {
      await connected(tester, <Map<String, Object?>>[
        _event('x', 'Après-demain', DateTime(2026, 11, 25, 9)),
      ], now: DateTime(2026, 11, 23, 23, 59));
      expect(find.text('Après-demain'), findsNothing);

      await tester.pump(const Duration(minutes: 2));
      await settle(tester);

      expect(find.text('Après-demain'), findsOneWidget);
    });

    testWidgets('aucun événement : une phrase le dit', (
      WidgetTester tester,
    ) async {
      await connected(tester, <Map<String, Object?>>[]);

      expect(find.textContaining('home.upcoming.empty'.tr()), findsOneWidget);
    });

    testWidgets('chargement : ni « aucun événement » ni erreur', (
      WidgetTester tester,
    ) async {
      _writePrefs(<String, Object?>{'calendar_connected': true});
      final Completer<void> gate = Completer<void>();
      final FakeCalendarPlatform platform =
          FakeCalendarPlatform(
              status: 'fullAccess',
              events: <Map<String, Object?>>[
                _event('a', 'Point de 11 h', DateTime(2026, 11, 23, 11)),
              ],
            )
            ..eventsGate = gate.future
            ..install();

      await pumpHome(tester);

      expect(find.textContaining('home.upcoming.empty'.tr()), findsNothing);
      expect(find.textContaining('home.upcoming.error'.tr()), findsNothing);
      expect(platform.callsTo('events'), isNotEmpty);
      gate.complete();
      await settle(tester);
      expect(find.text('Point de 11 h'), findsOneWidget);
    });

    testWidgets('lecture en échec : un message et « Réessayer » qui relit', (
      WidgetTester tester,
    ) async {
      _writePrefs(<String, Object?>{'calendar_connected': true});
      final FakeCalendarPlatform platform =
          FakeCalendarPlatform(
              status: 'fullAccess',
              events: <Map<String, Object?>>[
                _event('a', 'Point de 11 h', DateTime(2026, 11, 23, 11)),
              ],
            )
            ..eventsErrorCode = 'EVENTKIT_ERROR'
            ..install();
      await pumpHome(tester);

      expect(find.textContaining('home.upcoming.error'.tr()), findsOneWidget);
      platform.eventsErrorCode = null;
      await tapText(tester, 'common.action.retry'.tr());

      expect(find.text('Point de 11 h'), findsOneWidget);
      expect(find.textContaining('home.upcoming.error'.tr()), findsNothing);
    });
  });

  testWidgets('aujourd\'hui, un événement sans note n\'est pas inventé dans '
      'l\'historique', (WidgetTester tester) async {
    _writePrefs(<String, Object?>{'calendar_connected': true});
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[
        _event('passe', 'Réunion du matin', DateTime(2026, 11, 23, 8)),
        _event('a', 'Point de 11 h', DateTime(2026, 11, 23, 11)),
      ],
    ).install();

    await pumpHome(tester);

    // Fini et sans note : ni dans « À venir », ni dans l'historique.
    expect(find.text('Réunion du matin'), findsNothing);
    expect(find.text('common.label.today'.tr()), findsNothing);
  });
}
