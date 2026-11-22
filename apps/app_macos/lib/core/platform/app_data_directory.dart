import 'dart:io';

import 'package:flutter/foundation.dart';

/// Mode de compilation, injecté dans les fonctions pures ci-dessous.
enum AppBuildMode { debug, profile, release }

const String _appSupport = 'Library/Application Support';
const String _logs = 'Library/Logs';
const String _devName = 'Oats-dev';

/// Dossiers temporaires propres à ce processus de test, créés une seule fois :
/// deux lancements de tests ne partagent jamais d'état. Données et outils
/// sont distincts pour pouvoir vérifier qui écrit où.
final String _testDirectory = Directory.systemTemp
    .createTempSync('ici_transcript_test_')
    .path;
final String _testToolsDirectory = Directory.systemTemp
    .createTempSync('ici_transcript_tools_test_')
    .path;

bool _isUnderTest(Map<String, String> environment) =>
    environment.containsKey('FLUTTER_TEST');

String _home(Map<String, String> environment) => environment['HOME'] ?? '/tmp';

/// Le vrai dossier de l'app installée.
String _realDirectory(Map<String, String> environment) =>
    '${_home(environment)}/$_appSupport/IciTranscript';

/// `OATS_DATA_DIR` s'il est un chemin absolu ; vide, relatif ou `~` : ignoré.
String? _override(Map<String, String> environment) {
  final String? dir = environment['OATS_DATA_DIR'];
  return dir != null && dir.startsWith('/') ? dir : null;
}

/// Seul point qui décide du dossier des données de l'utilisateur (base,
/// prefs.json, enregistrements, transcriptions).
///
/// Ordre : sous `flutter test`, un dossier temporaire (incident 2026-11-22 :
/// un lancement de tests a migré la vraie base) ; puis `OATS_DATA_DIR`
/// absolu ; en debug/profile `Oats-dev` (un build de dev au schéma plus
/// récent rendrait la vraie base illisible pour la release installée) ; en
/// release le vrai dossier, inchangé.
String resolveAppDataDirectory(
  Map<String, String> environment, {
  required AppBuildMode buildMode,
}) {
  if (_isUnderTest(environment)) return _testDirectory;
  final String? override = _override(environment);
  if (override != null) return override;
  if (buildMode != AppBuildMode.release) {
    return '${_home(environment)}/$_appSupport/$_devName';
  }
  return _realDirectory(environment);
}

/// Caches d'outils volumineux (runtime et modèles Ollama, poids Nemotron) :
/// toujours le vrai dossier, pour ne pas les retélécharger en dev.
String resolveToolsDirectory(Map<String, String> environment) {
  if (_isUnderTest(environment)) return _testToolsDirectory;
  return _realDirectory(environment);
}

/// Vrai quand les données ne sont pas celles de l'utilisateur (debug,
/// profile, `OATS_DATA_DIR`) : le dossier des outils, partagé avec la
/// release, n'est alors ni écrasé ni nettoyé. Faux sous `flutter test`.
bool usesDevDataDirectory(
  Map<String, String> environment, {
  required AppBuildMode buildMode,
}) {
  if (_isUnderTest(environment)) return false;
  return _override(environment) != null || buildMode != AppBuildMode.release;
}

/// Scripts Python générés (réécrits à chaque usage) : à côté des outils en
/// release, comme avant ; dans le dossier de données sinon.
String resolveScriptsDirectory(
  Map<String, String> environment, {
  required AppBuildMode buildMode,
}) {
  final String base = usesDevDataDirectory(environment, buildMode: buildMode)
      ? resolveAppDataDirectory(environment, buildMode: buildMode)
      : resolveToolsDirectory(environment);
  return '$base/diar';
}

/// Dossier des journaux, suivant les mêmes règles que les données.
String resolveLogDirectory(
  Map<String, String> environment, {
  required AppBuildMode buildMode,
}) {
  if (_isUnderTest(environment)) return '$_testDirectory/Logs';
  final String? override = _override(environment);
  if (override != null) return '$override/Logs';
  final String name = buildMode == AppBuildMode.release
      ? 'iciTranscript'
      : _devName;
  return '${_home(environment)}/$_logs/$name';
}

// Seul endroit qui lit l'environnement et le mode de compilation réels.
AppBuildMode get _buildMode => currentBuildMode;

/// Mode de compilation de ce processus.
AppBuildMode get currentBuildMode => kReleaseMode
    ? AppBuildMode.release
    : kProfileMode
    ? AppBuildMode.profile
    : AppBuildMode.debug;

/// Dossier des données de l'utilisateur pour ce processus.
String appDataDirectory() =>
    resolveAppDataDirectory(Platform.environment, buildMode: _buildMode);

/// Dossier des caches d'outils pour ce processus.
String toolsDirectory() => resolveToolsDirectory(Platform.environment);

/// Dossier des scripts de diarization/traduction générés.
String scriptsDirectory() =>
    resolveScriptsDirectory(Platform.environment, buildMode: _buildMode);

/// Dossier des journaux pour ce processus.
String logDirectory() =>
    resolveLogDirectory(Platform.environment, buildMode: _buildMode);

/// Ce processus tourne-t-il sur des données de dev ?
bool runsOnDevDataDirectory() =>
    usesDevDataDirectory(Platform.environment, buildMode: _buildMode);
