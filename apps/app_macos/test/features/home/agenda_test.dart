import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/localized_app.dart';

SessionEntity _s(String id, DateTime start, {String? title, int? seconds}) =>
    FakeData.createSession(
      id: id,
      title: title ?? id,
      createdAt: start,
      updatedAt: start,
      durationSeconds: seconds,
    );

List<String> _ids(AgendaDay d) =>
    d.sessions.map((SessionEntity s) => s.id).toList();

void main() {
  group('groupSessionsByDay', () {
    test('regroupe par jour, le jour le plus récent en premier', () {
      final List<AgendaDay> days = groupSessionsByDay(<SessionEntity>[
        _s('mer-matin', DateTime(2026, 11, 18, 9)),
        _s('ven-soir', DateTime(2026, 11, 20, 18, 30)),
        _s('dim', DateTime(2026, 11, 22, 10)),
        _s('ven-matin', DateTime(2026, 11, 20, 8, 15)),
        _s('mer-soir', DateTime(2026, 11, 18, 21)),
      ]);

      expect(days.map((AgendaDay d) => d.day).toList(), <DateTime>[
        DateTime(2026, 11, 22),
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 18),
      ]);
      expect(_ids(days[1]), <String>['ven-soir', 'ven-matin']);
      expect(_ids(days[2]), <String>['mer-soir', 'mer-matin']);
    });

    test('minuit appartient au nouveau jour, 23:59 à la veille', () {
      final List<AgendaDay> days = groupSessionsByDay(<SessionEntity>[
        _s('minuit', DateTime(2026, 11, 21)),
        _s('tard', DateTime(2026, 11, 20, 23, 59)),
      ]);

      expect(days.length, 2);
      expect(days[0].day, DateTime(2026, 11, 21));
      expect(_ids(days[0]), <String>['minuit']);
      expect(days[1].day, DateTime(2026, 11, 20));
      expect(_ids(days[1]), <String>['tard']);
    });

    test('aucune session donne un agenda vide', () {
      expect(groupSessionsByDay(<SessionEntity>[]), isEmpty);
    });
  });

  group('formatDayHeader', () {
    // Les données de date « fr » et les traductions sont chargées par le
    // MaterialApp localisé : on le pompe une fois avant d'appeler la fonction.
    Future<void> load(WidgetTester tester) =>
        pumpLocalized(tester, const SizedBox());

    final DateTime now = DateTime(2026, 11, 22, 15);

    testWidgets("aujourd'hui s'affiche « Aujourd'hui »", (
      WidgetTester tester,
    ) async {
      await load(tester);
      expect(
        formatDayHeader(DateTime(2026, 11, 22), now: now),
        'common.label.today'.tr(),
      );
    });

    testWidgets('la veille s\'affiche « Hier »', (WidgetTester tester) async {
      await load(tester);
      expect(
        formatDayHeader(DateTime(2026, 11, 21), now: now),
        'common.label.yesterday'.tr(),
      );
    });

    testWidgets('un jour plus ancien affiche jour abrégé, quantième et mois', (
      WidgetTester tester,
    ) async {
      await load(tester);
      expect(formatDayHeader(DateTime(2026, 11, 20), now: now), 'ven. 20 nov.');
    });

    testWidgets('juste après minuit, 23:59 la veille reste « Hier »', (
      WidgetTester tester,
    ) async {
      await load(tester);
      expect(
        formatDayHeader(
          DateTime(2026, 11, 21, 23, 59),
          now: DateTime(2026, 11, 22, 0, 0, 1),
        ),
        'common.label.yesterday'.tr(),
      );
    });
  });

  group('formatStartTime', () {
    test('affiche l\'heure de début en HH:mm', () {
      expect(formatStartTime(DateTime(2026, 11, 20, 9, 5)), '09:05');
      expect(formatStartTime(DateTime(2026, 11, 20, 18, 30)), '18:30');
    });
  });

  group('formatDuration', () {
    test('moins d\'une heure : minutes', () {
      expect(formatDuration(52 * 60), '52 min');
    });

    test('une heure ou plus : heures et minutes sur deux chiffres', () {
      expect(formatDuration(67 * 60), '1 h 07');
      expect(formatDuration(125 * 60), '2 h 05');
    });

    test('durée inconnue : rien', () {
      expect(formatDuration(null), isNull);
    });
  });

  group('filterSessionsByTitle', () {
    final List<SessionEntity> sessions = <SessionEntity>[
      _s('a', DateTime(2026, 11, 20), title: 'Déploiements'),
      _s('b', DateTime(2026, 11, 20), title: 'Point équipe'),
      _s('c', DateTime(2026, 11, 19), title: 'Revue de DÉPLOIEMENT'),
    ];

    List<String> ids(List<SessionEntity> l) =>
        l.map((SessionEntity s) => s.id).toList();

    test('ignore casse et accents', () {
      expect(ids(filterSessionsByTitle(sessions, 'deploi')), <String>['a', 'c']);
      expect(ids(filterSessionsByTitle(sessions, 'ÉQUIPE')), <String>['b']);
    });

    test('requête vide : toutes les sessions', () {
      expect(ids(filterSessionsByTitle(sessions, '')), <String>['a', 'b', 'c']);
    });

    test('aucun titre ne correspond : liste vide', () {
      expect(filterSessionsByTitle(sessions, 'budget'), isEmpty);
    });
  });
}
