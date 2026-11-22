import 'dart:io';

/// Dossier temporaire propre à ce processus de test, créé une seule fois :
/// deux lancements de tests ne partagent jamais d'état.
final String _testDirectory = Directory.systemTemp
    .createTempSync('ici_transcript_test_')
    .path;

bool _isUnderTest(Map<String, String> environment) =>
    environment.containsKey('FLUTTER_TEST');

/// Seul point qui décide du dossier de données de l'app.
///
/// En production : `~/Library/Application Support/IciTranscript` (chemin
/// inchangé, les sessions et les modèles y vivent). Sous `flutter test`
/// (FLUTTER_TEST présent) : un dossier temporaire, jamais le vrai dossier
/// (incident 2026-11-22 : un lancement de tests a migré la vraie base).
String resolveAppDataDirectory(Map<String, String> environment) {
  if (_isUnderTest(environment)) return _testDirectory;
  final String home = environment['HOME'] ?? '/tmp';
  return '$home/Library/Application Support/IciTranscript';
}

/// Dossier de données de l'app pour l'environnement courant.
String appDataDirectory() => resolveAppDataDirectory(Platform.environment);

/// Dossier des journaux : `~/Library/Logs/iciTranscript` en production,
/// sous le dossier temporaire de test sous `flutter test`.
String logDirectory() {
  final Map<String, String> environment = Platform.environment;
  if (_isUnderTest(environment)) return '$_testDirectory/Logs';
  final String home = environment['HOME'] ?? '/tmp';
  return '$home/Library/Logs/iciTranscript';
}
