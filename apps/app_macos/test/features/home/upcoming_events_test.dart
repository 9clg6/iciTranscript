import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/home/presentation/widgets/upcoming_events.widget.dart';

import '../../helpers/localized_app.dart';

/// Bloc « À venir » : la synchro agenda arrive plus tard (T5) ; pour T0a,
/// un état vide explicite et l'acceptation d'une liste d'événements.
void main() {
  testWidgets('sans agenda connecté : titre et état vide explicite', (
    WidgetTester tester,
  ) async {
    await pumpLocalized(
      tester,
      const UpcomingEventsBlock(events: <UpcomingEvent>[]),
    );

    expect(find.text('home.upcoming.title'.tr()), findsOneWidget);
    expect(
      find.textContaining('home.upcoming.no_calendar'.tr()),
      findsOneWidget,
    );
  });

  testWidgets('avec des événements : titre, heure de début et participants', (
    WidgetTester tester,
  ) async {
    await pumpLocalized(
      tester,
      UpcomingEventsBlock(
        calendarConnected: true,
        events: <UpcomingEvent>[
          UpcomingEvent(
            title: 'Comité produit',
            start: DateTime(2026, 11, 23, 10, 30),
            attendeesCount: 4,
          ),
        ],
      ),
    );

    expect(find.text('Comité produit'), findsOneWidget);
    expect(find.textContaining('10:30'), findsOneWidget);
    expect(find.textContaining('4'), findsOneWidget);
    expect(find.textContaining('home.upcoming.no_calendar'.tr()), findsNothing);
  });
}
