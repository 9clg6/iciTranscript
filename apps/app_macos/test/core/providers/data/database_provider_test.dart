import 'dart:async';
import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';

/// Incident 2026-11-22 : tout test qui lisait databaseProvider sans override
/// ouvrait la vraie base de l'utilisateur. Sous `flutter test`, le provider
/// doit ouvrir une base jetable, sans que le test ait à le surcharger.
///
/// Sécurité : la lecture du provider se fait dans un piège IOOverrides qui
/// refuse de construire tout File/Directory sous Application Support. La base
/// n'est interrogée (ouverture SQLite par FFI, hors piège) qu'une fois les
/// chemins vérifiés.
void main() {
  bool isUnderRealDir(String path) =>
      path.contains('/Library/Application Support/');

  test(
    'sous flutter test, sans override, la base n\'est pas la vraie',
    () async {
      final String home = Platform.environment['HOME'] ?? '/tmp';
      final String realDir = '$home/Library/Application Support/IciTranscript';
      final List<String> touched = <String>[];
      final List<String> refused = <String>[];

      Never refuse(String path) {
        refused.add(path);
        throw StateError('Test interdit : vrai dossier de données ($path)');
      }

      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      AppDatabase? db;
      Object? buildError;
      IOOverrides.runZoned(
        () {
          // Le piège doit être actif avant toute lecture du provider.
          expect(() => Directory(realDir), throwsStateError);
          refused.clear();
          try {
            db = container.read(databaseProvider);
          } catch (error) {
            buildError = error;
          }
        },
        createDirectory: (String path) {
          if (isUnderRealDir(path)) refuse(path);
          touched.add(path);
          return Zone.root.run(() => Directory(path));
        },
        createFile: (String path) {
          if (isUnderRealDir(path)) refuse(path);
          touched.add(path);
          return Zone.root.run(() => File(path));
        },
      );

      expect(
        refused,
        isEmpty,
        reason: 'databaseProvider vise le vrai dossier de données.',
      );
      expect(buildError, isNull);
      final String dbPath = touched.lastWhere(
        (String p) => p.endsWith('.sqlite'),
        orElse: () => fail('Aucun fichier .sqlite construit : $touched'),
      );
      expect(isUnderRealDir(dbPath), isFalse);

      // Chemins vérifiés : la base peut être ouverte sans risque.
      final List<String> files =
          (await db!.customSelect('PRAGMA database_list').get())
              .map((row) => row.read<String>('file'))
              .toList();
      expect(files, isNotEmpty);
      for (final String file in files) {
        expect(isUnderRealDir(file), isFalse, reason: file);
      }
    },
  );
}
