import 'dart:io';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Revue PR #19, points 1 et 2 : ce que la dictée laisse derrière elle.
///
/// Hors réunion, rien : ni session, ni segment, ni fichier dans le dossier
/// des enregistrements (WAV, intervalles dictés), ni transcription .txt, et
/// le texte dicté n'est jamais écrit dans le journal — que la dictée ait
/// produit son texte, ait été annulée ou n'ait rien entendu.
/// Pendant une réunion : le texte dicté n'est ni dans la note, ni dans ce
/// que la réunion exporte à l'arrêt (segments de la session), ni dans le
/// journal.
///
/// Dossier de données temporaire des tests ; dépôts en mémoire ; journal
/// redirigé vers un fichier temporaire (`Log.writeToFile`).
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );
  const String secret = 'Mot secret dicté 4711';
  const String marker = 'repère-du-journal-de-test';
  late File logFile;

  setUpAll(() async {
    logFile = File(
      '${Directory.systemTemp.createTempSync('oats_dictation_log_').path}/app.log',
    );
    Log.writeToFile(logFile.path);
    // Première écriture hors de fake_async : le tuyau vers le fichier naît
    // dans la vraie zone, les écritures faites sous horloge factice partent.
    Log.named('spec').info('ouverture du journal');
    for (
      int i = 0;
      i < 50 && !logFile.readAsStringSync().contains('ouverture');
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(logFile.readAsStringSync(), contains('ouverture'));
  });

  setUp(() {
    for (final String dir in <String>[
      LiveTranscriptionService.recordingsDir,
      '${appDataDirectory()}/transcripts',
    ]) {
      expect(dir, startsWith(Directory.systemTemp.path));
      final Directory d = Directory(dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// Le journal une fois écrit sur disque (écritures asynchrones).
  Future<String> logContents() async {
    for (int i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (logFile.existsSync() && logFile.readAsStringSync().contains(marker)) {
        break;
      }
    }
    final String text = logFile.readAsStringSync();
    expect(text, contains(marker), reason: 'le journal de test est capté');
    return text;
  }

  List<String> filesUnder(String dir) => Directory(dir).existsSync()
      ? Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .map((File f) => f.path)
            .toList()
      : <String>[];

  void expectNoTrace(DictationHarness d) {
    expect(d.live.sessions.store, isEmpty, reason: 'aucune session');
    expect(d.live.segments.store, isEmpty, reason: 'aucun segment');
    expect(d.live.recorders, isEmpty, reason: 'aucun enregistreur WAV');
    expect(filesUnder(LiveTranscriptionService.recordingsDir), isEmpty);
    expect(filesUnder('${appDataDirectory()}/transcripts'), isEmpty);
  }

  group('hors réunion : aucune trace', () {
    test('dictée produite', () async {
      late DictationHarness d;
      fakeAsync((FakeAsync async) {
        d = DictationHarness(async)..launch(clipboardMode);
        Log.named('spec').info(marker);
        d.holdAndSay(10);
        d.remote.emitDone(secret);
        async.elapse(const Duration(seconds: 2));
        expect(d.output.copies, <String>[secret]);
      });

      expectNoTrace(d);
      expect(await logContents(), isNot(contains(secret)));
    });

    test('dictée annulée', () async {
      late DictationHarness d;
      fakeAsync((FakeAsync async) {
        d = DictationHarness(async)..launch(clipboardMode);
        Log.named('spec').info(marker);
        d.press();
        d.say(10);
        d.remote.emitDelta(secret);
        d.cancel();
        d.remote.emitDone(secret);
        async.elapse(const Duration(seconds: 2));
        expect(d.state, isA<DictationIdle>());
      });

      expectNoTrace(d);
      expect(await logContents(), isNot(contains(secret)));
    });

    test('rien entendu', () async {
      late DictationHarness d;
      fakeAsync((FakeAsync async) {
        d = DictationHarness(async)..launch(clipboardMode);
        Log.named('spec').info(marker);
        d.holdAndSay(10);
        d.remote.emitDone(secret, hadSpeech: false);
        async.elapse(const Duration(seconds: 2));
        expect(d.state, isA<DictationNothingHeard>());
      });

      expectNoTrace(d);
      expect(await logContents(), isNot(contains(secret)));
    });
  });

  test('pendant une réunion : ni dans la note, ni dans ce qu elle exporte à '
      'l arrêt, ni dans le journal', () async {
    late LiveServiceHarness h;
    late DictationHarness d;
    fakeAsync((FakeAsync async) {
      final FakeVoxServer server = FakeVoxServer();
      final FakeVoxSocket mic = FakeVoxSocket(server);
      final List<String> replies = <String>[
        'Réunion avant.',
        secret,
        'Réunion après.',
      ];
      mic.reply = (int n) => n <= replies.length ? replies[n - 1] : 'En trop.';
      h = LiveServiceHarness(
        async,
        remote: TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        ),
      );
      d = DictationHarness(async, live: h)..launch(clipboardMode);
      h.start(outputEnabled: false);
      Log.named('spec').info(marker);
      int id = 0;
      void run(int count, {bool voiced = true}) {
        for (int i = 0; i < count; i++) {
          h.audio.emit(
            chunk(
              AudioSource.input,
              id,
              timestampMs: h.t0 + id * 100,
              voiced: voiced,
            ),
          );
          id++;
          async.elapse(const Duration(milliseconds: 100));
        }
      }

      run(20);
      d.press();
      run(30);
      d.release();
      run(20);
      run(20, voiced: false);
      async.elapse(const Duration(seconds: 2));
      expect(d.output.copies, <String>[secret]);
      h.stop();
    });

    final List<String> exported = h.service.segmentsStream.value
        .map((TranscriptSegmentEntity s) => s.text)
        .toList();
    expect(exported, contains('Réunion après.'));
    expect(exported, isNot(contains(secret)));
    expect(
      h.segments.store.values.map((TranscriptSegmentEntity s) => s.text),
      isNot(contains(secret)),
    );
    expect(await logContents(), isNot(contains(secret)));
  });
}
