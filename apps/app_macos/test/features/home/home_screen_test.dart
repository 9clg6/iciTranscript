import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Accueil « agenda » : sessions passées groupées par jour, recherche,
/// bloc « À venir » au-dessus, état vide avec un moyen de démarrer une note.
void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime older = DateTime(now.year, now.month, now.day - 3, 10);

  final List<SessionEntity> sessions = <SessionEntity>[
    FakeData.createSession(
      id: 'deploy',
      title: 'Déploiements',
      createdAt: older,
      updatedAt: older,
      durationSeconds: 67 * 60,
    ),
    FakeData.createSession(
      id: 'point',
      title: 'Point équipe',
      createdAt: today.add(const Duration(hours: 9)),
      updatedAt: today.add(const Duration(hours: 9)),
      durationSeconds: 52 * 60,
    ),
    FakeData.createSession(
      id: 'revue',
      title: 'Revue produit',
      createdAt: today.add(const Duration(hours: 14, minutes: 30)),
      updatedAt: today.add(const Duration(hours: 14, minutes: 30)),
    ),
  ];

  Future<void> pumpHome(
    WidgetTester tester,
    List<SessionEntity> list,
  ) => pumpLocalized(
    tester,
    const HomeScreen(),
    overrides: <Override>[
      sessionListViewModelProvider.overrideWith(
        () => FakeSessionListViewModel(list),
      ),
    ],
  );

  testWidgets('affiche les jours du plus récent au plus ancien, '
      'les sessions du jour de la plus récente à la plus ancienne', (
    WidgetTester tester,
  ) async {
    final double Function(Finder) top = _top(tester);
    await pumpHome(tester, sessions);

    final Finder todayHeader = find.text('common.label.today'.tr());
    final Finder olderHeader = find.text(formatDayHeader(older, now: now));
    expect(todayHeader, findsOneWidget);
    expect(olderHeader, findsOneWidget);

    expect(top(todayHeader), lessThan(top(find.text('Revue produit'))));
    expect(
      top(find.text('Revue produit')),
      lessThan(top(find.text('Point équipe'))),
    );
    expect(top(find.text('Point équipe')), lessThan(top(olderHeader)));
    expect(top(olderHeader), lessThan(top(find.text('Déploiements'))));
  });

  testWidgets('chaque ligne montre titre, heure de début et durée lisible', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, sessions);

    expect(find.text('Point équipe'), findsOneWidget);
    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('52 min'), findsOneWidget);
    expect(find.textContaining('10:00'), findsOneWidget);
    expect(find.textContaining('1 h 07'), findsOneWidget);
  });

  testWidgets('sans durée connue, la ligne garde titre et heure', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, sessions);

    expect(find.text('Revue produit'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
    // Seule « Point équipe » a une durée en minutes : rien pour « Revue produit ».
    expect(find.textContaining(' min'), findsOneWidget);
  });

  testWidgets('sans session : une phrase et un bouton pour démarrer une note', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, <SessionEntity>[]);

    expect(find.textContaining('home.empty'.tr()), findsOneWidget);
    expect(find.text('home.new_note'.tr()).hitTestable(), findsWidgets);
    expect(find.text('common.label.today'.tr()), findsNothing);
  });

  testWidgets('la recherche « deploi » trouve « Déploiements » '
      'et garde son en-tête de jour', (WidgetTester tester) async {
    await pumpHome(tester, sessions);

    await tester.enterText(find.byType(TextField), 'deploi');
    await tester.pumpAndSettle();

    expect(find.text('Déploiements'), findsOneWidget);
    expect(find.text(formatDayHeader(older, now: now)), findsOneWidget);
    expect(find.text('Point équipe'), findsNothing);
    expect(find.text('Revue produit'), findsNothing);
    expect(find.text('common.label.today'.tr()), findsNothing);
  });

  testWidgets('le bloc « À venir » est au-dessus de l\'historique '
      'et dit qu\'aucun agenda n\'est connecté', (WidgetTester tester) async {
    final double Function(Finder) top = _top(tester);
    await pumpHome(tester, sessions);

    final Finder upcoming = find.text('home.upcoming.title'.tr());
    expect(upcoming, findsOneWidget);
    expect(find.textContaining('home.upcoming.no_calendar'.tr()), findsOneWidget);
    expect(top(upcoming), lessThan(top(find.text('common.label.today'.tr()))));
  });
}

double Function(Finder) _top(WidgetTester tester) =>
    (Finder f) => tester.getTopLeft(f.first).dy;
