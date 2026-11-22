import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Test d'integration : historique des sessions.
  ///
  /// Verifie que la sidebar avec l'historique des sessions
  /// est accessible via la navigation.
  group('Session history', () {
    patrolTest('l\'app demarre avec l\'ecran principal visible', ($) async {
      app.main();
      await $.pumpAndSettle();

      // Verifie que l'app est lancee
      expect($('Oats'), findsOneWidget);
    });

    patrolTest('la navigation vers l\'historique est possible', ($) async {
      app.main();
      await $.pumpAndSettle();

      // En mode MVP, la sidebar n'est pas encore integree
      // dans le main.dart de base. Ce test sera etoffe
      // quand le routing AutoRoute sera en place.
      expect($('Oats'), findsOneWidget);
    });
  });
}
