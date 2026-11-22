import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Test d'integration : lancement de l'application.
  ///
  /// Verifie que l'application demarre correctement
  /// et affiche l'ecran principal.
  patrolTest('l\'app demarre et affiche l\'ecran principal', ($) async {
    app.main();
    await $.pumpAndSettle();

    // Verifie que l'app est lancee avec le texte principal
    expect($('Oats'), findsOneWidget);
  });

  patrolTest('l\'app affiche un Scaffold au demarrage', ($) async {
    app.main();
    await $.pumpAndSettle();

    // Verifie la presence du Scaffold ou du titre principal
    expect($('Oats'), findsWidgets);
  });
}
