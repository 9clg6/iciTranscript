import 'package:core_foundation/config/app_config.dart';
import 'package:core_foundation/enum/environment.enum.dart';

/// Configuration de l'environnement de staging.
final class AppConfigStaging extends AppConfig {
  /// Cree une instance de [AppConfigStaging].
  const AppConfigStaging()
    : super(
        appName: 'iciTranscript Staging',
        baseUrl: 'https://api-staging.icitranscript.fr',
        env: Environment.staging,
      );
}
