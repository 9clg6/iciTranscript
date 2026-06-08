import 'package:core_foundation/config/app_config.dart';
import 'package:core_foundation/enum/environment.enum.dart';

/// Configuration de l'environnement de production.
final class AppConfigProd extends AppConfig {
  /// Cree une instance de [AppConfigProd].
  const AppConfigProd()
    : super(
        appName: 'iciTranscript',
        baseUrl: 'https://api.icitranscript.fr',
        env: Environment.production,
      );
}
