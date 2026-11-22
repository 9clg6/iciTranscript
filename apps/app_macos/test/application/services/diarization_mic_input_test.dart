import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

/// Revue PR #19, point 2 : la passe post-réunion (diarization) reçoit le
/// micro sans les mots dictés, mais l'enregistrement de l'utilisateur reste
/// intact sur disque : le silence est mis sur une copie.
///
/// API supposée sur [DiarizationService] :
/// `Future<String> micInputWithoutDictation(String sessionId)` — chemin du
/// WAV micro à donner à la passe : le WAV lui-même sans dictée, sinon une
/// copie avec les intervalles dictés en silence. (Ce que `processSession`
/// utilise ; exposé pour être vérifié sans lancer le script Python.)
void main() {
  const String sessionId = '1700000000000';
  late String dir;
  late String micPath;

  setUp(() async {
    dir = LiveTranscriptionService.recordingsDir;
    expect(dir, startsWith(Directory.systemTemp.path));
    final Directory d = Directory(dir);
    if (d.existsSync()) await d.delete(recursive: true);
    await d.create(recursive: true);
    micPath = '$dir/${sessionId}_mic.wav';
    final WavRecorder recorder = WavRecorder();
    await recorder.open(micPath);
    for (int i = 0; i < 50; i++) {
      final Uint8List data = Uint8List(3200);
      final ByteData samples = ByteData.sublistView(data);
      for (int at = 0; at < data.length; at += 2) {
        samples.setInt16(at, 1000, Endian.little);
      }
      await recorder.append(data);
    }
    await recorder.close();
  });

  int sampleAt(Uint8List wav, int ms) =>
      ByteData.sublistView(wav).getInt16(44 + ms * 32, Endian.little);

  test('avec une dictée : copie en silence, l enregistrement intact', () async {
    final Uint8List before = File(micPath).readAsBytesSync();
    DictatedIntervalsStore(
      dir,
    ).add(sessionId, const DictatedInterval(startMs: 1000, endMs: 2000));

    final String input = await DiarizationService().micInputWithoutDictation(
      sessionId,
    );

    expect(input, isNot(micPath));
    expect(File(micPath).readAsBytesSync(), before, reason: 'WAV intact');
    final Uint8List muted = File(input).readAsBytesSync();
    expect(sampleAt(muted, 500), 1000);
    expect(sampleAt(muted, 1500), 0);
    expect(muted.length, before.length);
  });

  test('sans dictée : le WAV lui-même, intact', () async {
    final Uint8List before = File(micPath).readAsBytesSync();

    final String input = await DiarizationService().micInputWithoutDictation(
      sessionId,
    );

    expect(input, micPath);
    expect(File(micPath).readAsBytesSync(), before);
  });
}
