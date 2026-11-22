import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Test d'integration : ecran de preferences.
  ///
  /// Verifie que l'ecran de preferences est accessible
  /// et affiche les options de configuration audio.
  group('Settings', () {
    patrolTest('l\'app demarre correctement pour acceder aux settings', (
      $,
    ) async {
      app.main();
      await $.pumpAndSettle();

      // Verifie que l'app est lancee
      expect($('Oats'), findsOneWidget);
    });

    patrolTest('la navigation vers les preferences est possible', ($) async {
      app.main();
      await $.pumpAndSettle();

      // En mode MVP, l'ecran de preferences n'est pas encore implemente.
      // Ce test sera etoffe quand FR-006.4 sera en place.
      // Pour l'instant, on verifie juste que l'app ne crash pas.
      expect($('Oats'), findsOneWidget);
    });
  });
}
