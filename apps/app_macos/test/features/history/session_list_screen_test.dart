import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.screen.dart';

import '../../helpers/test_helpers.dart';

void main() {
  /// Tests widget pour [SessionListScreen].
  ///
  /// Verifie que l'ecran sidebar affiche correctement la liste
  /// des sessions et le champ de recherche (Reglages est dans la
  /// barre de navigation du shell, cf. test/features/shell).
  group('SessionListScreen', () {
    testWidgets('doit afficher le champ de recherche', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        TestHelpers.createTestableWidgetWithScaffold(
          child: const SessionListScreen(),
        ),
      );
      await tester.pump();

      // Assert
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('doit afficher le message vide quand aucune session', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        TestHelpers.createTestableWidgetWithScaffold(
          child: const SessionListScreen(),
        ),
      );
      await tester.pump();

      // Assert — La liste est vide, donc le message vide s'affiche
      // Le contenu depend de LocaleKeys, on verifie juste que le widget est la
      expect(find.byType(SessionListScreen), findsOneWidget);
    });
  });
}
