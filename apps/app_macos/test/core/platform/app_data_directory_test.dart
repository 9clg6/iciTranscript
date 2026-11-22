import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Un seul point décide du dossier de données de l'app. Sous `flutter test`
/// (FLUTTER_TEST présent), il ne doit jamais désigner le vrai dossier
/// (incident 2026-11-22 : un lancement de tests a migré la vraie base).
void main() {
  // HOME fictif : prouve que la fonction lit son paramètre et non
  // Platform.environment. Aucune I/O sur ce chemin.
  const String fakeHome = '/Users/someone';
  const String realDir = '$fakeHome/Library/Application Support/IciTranscript';

  test('en production, le dossier de données est Application Support', () {
    final String dir = resolveAppDataDirectory(<String, String>{
      'HOME': fakeHome,
    });

    expect(dir, realDir);
  });

  test(
    'sous flutter test, le dossier de données est un dossier temporaire',
    () {
      final String dir = resolveAppDataDirectory(<String, String>{
        'HOME': fakeHome,
        'FLUTTER_TEST': 'true',
      });

      expect(dir, isNot(startsWith('$fakeHome/Library/Application Support')));
      expect(dir, startsWith(Directory.systemTemp.path));
    },
  );

  test(
    'sans paramètre, sous flutter test, ce n\'est jamais le vrai dossier',
    () {
      final String home = Platform.environment['HOME'] ?? '/tmp';

      final String dir = appDataDirectory();

      expect(dir, isNot(startsWith('$home/Library/Application Support')));
      expect(dir, startsWith(Directory.systemTemp.path));
    },
  );
}
