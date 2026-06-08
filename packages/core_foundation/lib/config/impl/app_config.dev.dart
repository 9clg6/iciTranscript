import 'package:core_foundation/config/app_config.dart';
import 'package:core_foundation/enum/environment.enum.dart';

/// Configuration de l'environnement de developpement.
final class AppConfigDev extends AppConfig {
  /// Cree une instance de [AppConfigDev].
  const AppConfigDev()
    : super(
        appName: 'iciTranscript Dev',
        baseUrl: 'https://api-dev.icitranscript.fr',
        env: Environment.development,
      );
}
