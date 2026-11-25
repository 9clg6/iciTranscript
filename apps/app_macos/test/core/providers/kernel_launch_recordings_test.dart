import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';

/// Tour 3 de T1 : ce que le lancement fait aux enregistrements.
///
/// 1. No blanket purge at launch (decision 2026-11-25, "temporary audio
///    only", existing WAVs sorted by the user himself): launch deletes the
///    audio of a note only when it finishes that note's processing itself
///    (a session killed while `active`, or a note recorded as "processing
///    in progress"; see no_meeting_audio_test.dart). The WAVs of notes
///    finished before, with no such record, are never touched, whatever
///    their age or their session's state.
/// 2. La réparation des WAV ne touche qu'aux en-têtes non finalisés.
///
/// Base en mémoire ; dossier d'enregistrements = dossier temporaire de test
/// (vérifié avant toute écriture), jamais le vrai dossier de données.
void main() {
  late Directory recordings;
  late ProviderContainer container;
  final DateTime now = DateTime.now();

  setUp(() async {
    final String dir = LiveTranscriptionService.recordingsDir;
    expect(dir, startsWith(Directory.systemTemp.path));
    expect(dir, isNot(contains('/Library/Application Support/')));
    recordings = Directory(dir);
    if (recordings.existsSync()) await recordings.delete(recursive: true);
    await recordings.create(recursive: true);

    container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(
          AppDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> session(String id, SessionStatus status) => container
      .read(sessionRepositoryProvider)
      .create(
        SessionEntity(
          id: id,
          title: 'Réunion $id',
          createdAt: now.subtract(const Duration(days: 400)),
          updatedAt: now.subtract(const Duration(days: 400)),
          durationSeconds: 3600,
          status: status,
        ),
      );

  /// WAV bien finalisé, daté de [age].
  Future<File> healthyWav(String name, Duration age) async {
    final File file = File('${recordings.path}/$name');
    final WavRecorder recorder = WavRecorder();
    await recorder.open(file.path);
    await recorder.append(Uint8List(6400)..fillRange(0, 6400, 5));
    await recorder.close();
    await file.setLastModified(now.subtract(age));
    return file;
  }

  Future<File> rawFile(String name, List<int> bytes, Duration age) async {
    final File file = File('${recordings.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await file.setLastModified(now.subtract(age));
    return file;
  }

  Future<Map<String, (Uint8List, DateTime)>> snapshot() async =>
      <String, (Uint8List, DateTime)>{
        for (final File f in recordings.listSync().whereType<File>())
          f.path: (await f.readAsBytes(), f.lastModifiedSync()),
      };

  void expectUnchanged(
    Map<String, (Uint8List, DateTime)> before,
    Map<String, (Uint8List, DateTime)> after,
  ) {
    expect(after.keys, unorderedEquals(before.keys), reason: 'fichier perdu');
    for (final String path in before.keys) {
      expect(after[path]!.$1, before[path]!.$1, reason: 'contenu : $path');
      expect(after[path]!.$2, before[path]!.$2, reason: 'date : $path');
    }
  }

  test(
    'launch leaves untouched the recordings of notes finished before '
    '(no processing in progress), whatever their age or session state',
    () async {
      await session('1500000000000', SessionStatus.completed);
      await session('1400000000000', SessionStatus.interrupted);
      for (final (String id, Duration age) in <(String, Duration)>[
        ('1500000000000', const Duration(days: 730)), // terminée, 2 ans
        ('1400000000000', const Duration(days: 365)), // interrompue, 1 an
        ('1300000000000', const Duration(days: 90)), // absente de la base
        ('1200000000000', const Duration(days: 20)),
      ]) {
        await healthyWav('${id}_mic.wav', age);
        await healthyWav('${id}_system.wav', age);
      }
      final Map<String, (Uint8List, DateTime)> before = await snapshot();
      expect(before, hasLength(8));

      await container.read(kernelProvider.future);

      expectUnchanged(before, await snapshot());
    },
  );

  test('la réparation au lancement laisse intacts un WAV sain, un fichier '
      'non WAV, un faux WAV et un fichier plus court qu un en-tête', () async {
    await healthyWav('1500000000000_mic.wav', const Duration(days: 3));
    await rawFile('notes.txt', List<int>.filled(100, 42), Duration.zero);
    await rawFile(
      'not_riff.wav',
      List<int>.generate(100, (int i) => i),
      const Duration(days: 1),
    );
    await rawFile('tiny.wav', <int>[1, 2, 3], const Duration(days: 1));
    final Map<String, (Uint8List, DateTime)> before = await snapshot();

    await container.read(kernelProvider.future);

    expectUnchanged(before, await snapshot());
  });

  test('la réparation au lancement recale un WAV à l en-tête non '
      'finalisé', () async {
    final File healthy = await healthyWav('model.wav', Duration.zero);
    final Uint8List header = (await healthy.readAsBytes()).sublist(0, 44);
    await healthy.delete();
    ByteData.sublistView(header)
      ..setUint32(4, 36, Endian.little)
      ..setUint32(40, 0, Endian.little);
    final File crashed = await rawFile('1600000000000_mic.wav', <int>[
      ...header,
      ...List<int>.filled(32000, 7),
    ], const Duration(hours: 1));

    await container.read(kernelProvider.future);

    final ByteData h = ByteData.sublistView(await crashed.readAsBytes(), 0, 44);
    expect(h.getUint32(40, Endian.little), 32000);
    expect(h.getUint32(4, Endian.little), 36 + 32000);
  });
}
