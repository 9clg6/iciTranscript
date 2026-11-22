import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde structurelle : les vrais dossiers (données, journaux) ne sont écrits
/// qu'à un seul endroit, le résolveur. Tout autre chemin doit en dériver,
/// sinon un test ou un build de dev peut à nouveau écrire dans les données de
/// l'utilisateur.
void main() {
  const String resolverFile = 'lib/core/platform/app_data_directory.dart';

  for (final String literal in <String>[
    'Library/Application Support',
    'Library/Logs',
  ]) {
    test('"$literal" n\'apparaît que dans le résolveur', () {
      final List<File> sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .where((File f) => !f.path.endsWith('.g.dart'))
          .toList();
      // Évite un vert vide si le dossier courant n'est pas apps/app_macos.
      expect(sources, isNotEmpty);

      final List<String> offenders = <String>[];
      for (final File file in sources) {
        final String path = file.path.replaceAll(r'\', '/');
        if (path == resolverFile) continue;
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains(literal)) offenders.add('$path:${i + 1}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Dériver ces chemins du résolveur ($resolverFile).',
      );
    });
  }
}
