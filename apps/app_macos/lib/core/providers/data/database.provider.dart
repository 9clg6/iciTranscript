import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database.provider.g.dart';

/// Provider singleton pour [AppDatabase] (Drift/SQLite).
///
/// Base PERSISTANTE sur disque (sinon les sessions disparaissent au
/// redémarrage). Fichier dans le dossier de l'app.
@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  final String home = Platform.environment['HOME'] ?? '/tmp';
  final Directory dir = Directory(
    '$home/Library/Application Support/IciTranscript',
  )..createSync(recursive: true);
  final File dbFile = File('${dir.path}/ici_transcript.sqlite');
  final AppDatabase db = AppDatabase(NativeDatabase(dbFile));
  ref.onDispose(db.close);
  return db;
}
