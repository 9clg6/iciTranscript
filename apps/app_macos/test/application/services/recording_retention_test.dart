import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/recording_retention.dart';

/// Tour 2, point 6 : les WAV sont toujours écrits (~230 Mo par heure). Au
/// lancement, ceux de plus de 14 jours sont supprimés, sauf ceux d'une
/// session encore `active`. Les 14 jours viennent d'une seule constante.
///
/// Fichiers nommés `<sessionId>_mic.wav` / `<sessionId>_system.wav`. Le
/// dossier est un paramètre : le test n'utilise qu'un dossier temporaire.
void main() {
  final DateTime now = DateTime(2026, 11, 22, 9);
  const Duration maxAge = RecordingRetention.maxAge;
  final DateTime old = now.subtract(maxAge + const Duration(hours: 1));
  final DateTime recent = now.subtract(maxAge - const Duration(hours: 1));

  List<String> expired(
    Map<String, DateTime> files, {
    Set<String> active = const <String>{},
  }) => RecordingRetention.expired(
    <({String path, DateTime modified})>[
      for (final MapEntry<String, DateTime> f in files.entries)
        (path: '/rec/${f.key}', modified: f.value),
    ],
    activeSessionIds: active,
    now: now,
  );

  group('décision', () {
    test('la durée de conservation est de 14 jours', () {
      expect(RecordingRetention.maxAge, const Duration(days: 14));
    });

    test('supprime les deux pistes d une session de plus de 14 jours', () {
      expect(
        expired(<String, DateTime>{
          '1700_mic.wav': old,
          '1700_system.wav': old,
        }),
        unorderedEquals(<String>['/rec/1700_mic.wav', '/rec/1700_system.wav']),
      );
    });

    test('garde un enregistrement de moins de 14 jours', () {
      expect(expired(<String, DateTime>{'1800_mic.wav': recent}), isEmpty);
    });

    test('garde un vieil enregistrement d une session encore active', () {
      expect(
        expired(
          <String, DateTime>{'1700_mic.wav': old, '1700_system.wav': old},
          active: <String>{'1700'},
        ),
        isEmpty,
      );
    });

    test('une session active ne protège que ses propres fichiers', () {
      expect(
        expired(
          <String, DateTime>{'1700_mic.wav': old, '17000_mic.wav': old},
          active: <String>{'1700'},
        ),
        <String>['/rec/17000_mic.wav'],
      );
    });

    test('ne touche pas aux fichiers qui ne sont pas des WAV', () {
      expect(
        expired(<String, DateTime>{'notes.txt': old, 'app.log': old}),
        isEmpty,
      );
    });
  });

  group('dossier', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('oats_retention_');
    });

    tearDown(() => temp.delete(recursive: true));

    Future<File> file(String name, DateTime modified) async {
      final File f = File('${temp.path}/$name');
      await f.writeAsBytes(<int>[0, 1, 2, 3]);
      await f.setLastModified(modified);
      return f;
    }

    test('supprime seulement les vieux WAV des sessions closes', () async {
      final File oldMic = await file('1700_mic.wav', old);
      final File oldSystem = await file('1700_system.wav', old);
      final File activeMic = await file('1600_mic.wav', old);
      final File recentMic = await file('1800_mic.wav', recent);
      final File other = await file('notes.txt', old);

      await RecordingRetention.purge(
        temp.path,
        activeSessionIds: <String>{'1600'},
        now: now,
      );

      expect(oldMic.existsSync(), isFalse);
      expect(oldSystem.existsSync(), isFalse);
      expect(activeMic.existsSync(), isTrue);
      expect(recentMic.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
    });

    test('un dossier absent ne fait pas échouer le lancement', () async {
      await expectLater(
        RecordingRetention.purge(
          '${temp.path}/absent',
          activeSessionIds: const <String>{},
          now: now,
        ),
        completes,
      );
    });
  });
}
