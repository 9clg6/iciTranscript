import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde structurelle : l'app n'arrête que ce qu'elle a lancé, et chaque
/// port n'a qu'une source.
///
/// 1. Aucun kill par nom (`pkill`, `killall`, `kill -9 -f`) dans le code
///    Dart, ni `pkill`/`killall`/`pgrep` côté Swift : un build de dev
///    tuerait les serveurs de l'app installée, et l'inverse.
/// 2. Les ports 8000/8001 (et 11434 d'Ollama) ne s'écrivent que dans
///    `server_ports.dart` : URL WebSocket, /health, diarization et `--port`
///    en dérivent, sinon un build de dev parle au serveur de l'app installée.
/// 3. Lancer et tuer un processus passe par un seul adaptateur, l'hôte de
///    processus système, que les tests remplacent par un faux.
void main() {
  const String portsFile = 'lib/core/platform/server_ports.dart';
  const String hostFile = 'lib/core/platform/system_process_host.dart';

  bool isGenerated(String path) =>
      path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.endsWith('.gr.dart') ||
      path.startsWith('lib/generated/');

  List<File> sources(String root, String extension) {
    final List<File> files = Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith(extension))
        .where((File f) => !isGenerated(f.path.replaceAll(r'\', '/')))
        .toList();
    // Évite un vert vide si le dossier courant n'est pas apps/app_macos.
    expect(files, isNotEmpty, reason: '$root/**$extension');
    return files;
  }

  /// `chemin:ligne` de chaque ligne de [files] qui contient [pattern].
  List<String> offenders(List<File> files, Pattern pattern, {String? except}) {
    final List<String> found = <String>[];
    for (final File file in files) {
      final String path = file.path.replaceAll(r'\', '/');
      if (path == except) continue;
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains(pattern)) found.add('$path:${i + 1}');
      }
    }
    return found;
  }

  group('aucun kill par nom', () {
    for (final String literal in <String>['pkill', 'killall', 'kill -9 -f']) {
      test('"$literal" n\'apparaît pas dans lib/', () {
        expect(
          offenders(sources('lib', '.dart'), literal),
          isEmpty,
          reason: 'Tuer par PID noté (OwnedProcessRegistry), jamais par nom.',
        );
      });
    }

    for (final String literal in <String>['pkill', 'killall', 'pgrep']) {
      test('"$literal" n\'apparaît pas dans macos/Runner/', () {
        expect(
          offenders(sources('macos/Runner', '.swift'), literal),
          isEmpty,
          reason:
              'ProcessManagerPlugin.swift tue par nom (pgrep -f puis kill) ; '
              'Dart ne l\'appelle pas.',
        );
      });
    }
  });

  group('un seul fichier pour les ports', () {
    // Un port écrit en dur : dans une URL (`:8000`), une chaîne ('8000') ou
    // une affectation à un nom en *port* (`port = 8001`, `serverPort: …`).
    // Ne prend pas les autres nombres 8000 (ex. une limite de caractères).
    final RegExp port800x = RegExp(
      r'''(:800[01]\b)|(['"]800[01]['"])|(port\w*\s*[:=,(]\s*800[01]\b)''',
      caseSensitive: false,
    );

    test('8000 et 8001 ne s\'écrivent que dans $portsFile', () {
      expect(
        offenders(sources('lib', '.dart'), port800x, except: portsFile),
        isEmpty,
        reason: 'Dériver ports et URL de $portsFile.',
      );
    });

    test('11434 (Ollama) ne s\'écrit que dans $portsFile', () {
      expect(
        offenders(sources('lib', '.dart'), '11434', except: portsFile),
        isEmpty,
        reason: 'Dériver l\'URL d\'Ollama de $portsFile.',
      );
    });
  });

  group('lancer et tuer passent par l\'hôte de processus', () {
    for (final String literal in <String>[
      'Process.start(',
      'Process.killPid(',
      "'/bin/kill'",
    ]) {
      test('"$literal" n\'apparaît que dans $hostFile', () {
        expect(
          offenders(sources('lib', '.dart'), literal, except: hostFile),
          isEmpty,
          reason: 'Passer par ProcessHost (faux dans les tests).',
        );
      });
    }
  });
}
