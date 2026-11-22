import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Un seul point décide des dossiers de l'app. Sous `flutter test`, jamais le
/// vrai dossier (incident 2026-11-22 : un lancement de tests a migré la vraie
/// base). Un build lancé en debug ou profile ne touche pas non plus aux
/// données de l'utilisateur ; seul un build release les ouvre.
///
/// Tout passe par des fonctions pures (environnement et mode de build
/// injectés) : aucune I/O sur les chemins fictifs ci-dessous.
void main() {
  const String fakeHome = '/Users/someone';
  const String realDir = '$fakeHome/Library/Application Support/IciTranscript';
  const String devDir = '$fakeHome/Library/Application Support/Oats-dev';
  const String realLogs = '$fakeHome/Library/Logs/iciTranscript';
  const String devLogs = '$fakeHome/Library/Logs/Oats-dev';
  const String overrideDir = '/Volumes/scratch/oats-data';

  const Map<String, String> launched = <String, String>{'HOME': fakeHome};
  const Map<String, String> underTest = <String, String>{
    'HOME': fakeHome,
    'FLUTTER_TEST': 'true',
  };
  Map<String, String> withOverride(String value) => <String, String>{
    'HOME': fakeHome,
    'OATS_DATA_DIR': value,
  };

  String data(Map<String, String> env, AppBuildMode mode) =>
      resolveAppDataDirectory(env, buildMode: mode);

  group('données utilisateur : ordre de priorité', () {
    test('release : le vrai dossier, identique à aujourd\'hui', () {
      expect(data(launched, AppBuildMode.release), realDir);
    });

    test('debug : le dossier de dev Oats-dev, jamais le vrai', () {
      expect(data(launched, AppBuildMode.debug), devDir);
    });

    test('profile : le dossier de dev Oats-dev, jamais le vrai', () {
      expect(data(launched, AppBuildMode.profile), devDir);
    });

    for (final AppBuildMode mode in AppBuildMode.values) {
      test('${mode.name} : OATS_DATA_DIR absolu est utilisé tel quel', () {
        expect(data(withOverride(overrideDir), mode), overrideDir);
      });

      test('${mode.name} : sous flutter test, un dossier temporaire', () {
        final String dir = data(underTest, mode);

        expect(dir, startsWith(Directory.systemTemp.path));
        expect(dir, isNot(startsWith('$fakeHome/Library')));
      });

      test('${mode.name} : sous flutter test, OATS_DATA_DIR ne l\'emporte '
          'pas sur le dossier temporaire', () {
        final String dir = data(<String, String>{
          ...underTest,
          'OATS_DATA_DIR': overrideDir,
        }, mode);

        expect(dir, isNot(overrideDir));
        expect(dir, startsWith(Directory.systemTemp.path));
      });
    }

    const Map<String, String> ignored = <String, String>{
      'vide': '',
      'relatif': 'data',
      'relatif ./': './oats',
      'tilde non développé': '~/oats',
    };
    ignored.forEach((String name, String value) {
      test('OATS_DATA_DIR $name (« $value ») est ignoré', () {
        expect(data(withOverride(value), AppBuildMode.release), realDir);
        expect(data(withOverride(value), AppBuildMode.debug), devDir);
      });
    });

    test('sans paramètre, sous flutter test, ce n\'est jamais le vrai '
        'dossier ni le dossier de dev', () {
      final String home = Platform.environment['HOME'] ?? '/tmp';

      final String dir = appDataDirectory();

      expect(dir, isNot(startsWith('$home/Library/Application Support')));
      expect(dir, startsWith(Directory.systemTemp.path));
    });
  });

  group('caches d\'outils (Ollama, diarization) : partagés', () {
    test('restent sur le vrai dossier, quel que soit le mode, pour ne pas '
        'retélécharger les modèles', () {
      expect(resolveToolsDirectory(launched), realDir);
    });

    test('OATS_DATA_DIR ne déplace pas les caches d\'outils', () {
      expect(resolveToolsDirectory(withOverride(overrideDir)), realDir);
    });

    test('sous flutter test, un dossier temporaire', () {
      final String dir = resolveToolsDirectory(underTest);

      expect(dir, startsWith(Directory.systemTemp.path));
      expect(dir, isNot(startsWith('$fakeHome/Library')));
    });

    test('sous flutter test, distinct du dossier de données (sinon on ne '
        'peut pas vérifier qui écrit où)', () {
      expect(
        resolveToolsDirectory(underTest),
        isNot(data(underTest, AppBuildMode.debug)),
      );
    });

    test('sans paramètre, sous flutter test, ce n\'est jamais le vrai '
        'dossier', () {
      final String home = Platform.environment['HOME'] ?? '/tmp';

      final String dir = toolsDirectory();

      expect(dir, isNot(startsWith('$home/Library/Application Support')));
      expect(dir, startsWith(Directory.systemTemp.path));
    });
  });

  group('journaux', () {
    String logs(Map<String, String> env, AppBuildMode mode) =>
        resolveLogDirectory(env, buildMode: mode);

    test('release : le vrai dossier de journaux, inchangé', () {
      expect(logs(launched, AppBuildMode.release), realLogs);
    });

    test('debug : le dossier de journaux de dev', () {
      expect(logs(launched, AppBuildMode.debug), devLogs);
    });

    test('sous flutter test, un dossier temporaire', () {
      final String dir = logs(underTest, AppBuildMode.debug);

      expect(dir, startsWith(Directory.systemTemp.path));
      expect(dir, isNot(startsWith('$fakeHome/Library')));
    });

    test('sans paramètre, sous flutter test, ce n\'est jamais le vrai '
        'dossier', () {
      final String home = Platform.environment['HOME'] ?? '/tmp';

      expect(logDirectory(), isNot(startsWith('$home/Library/Logs')));
      expect(logDirectory(), startsWith(Directory.systemTemp.path));
    });
  });

  group('signal « données de dev »', () {
    bool dev(Map<String, String> env, AppBuildMode mode) =>
        usesDevDataDirectory(env, buildMode: mode);

    test('faux en release, sur le vrai dossier', () {
      expect(dev(launched, AppBuildMode.release), isFalse);
    });

    test('vrai en debug', () {
      expect(dev(launched, AppBuildMode.debug), isTrue);
    });

    test('vrai en profile', () {
      expect(dev(launched, AppBuildMode.profile), isTrue);
    });

    test('vrai en release avec OATS_DATA_DIR', () {
      expect(dev(withOverride(overrideDir), AppBuildMode.release), isTrue);
    });

    test('faux en release avec un OATS_DATA_DIR ignoré', () {
      expect(dev(withOverride('data'), AppBuildMode.release), isFalse);
    });
  });
}
