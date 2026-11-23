import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

/// Besoin T1.3 / T1.4 : l'audio d'une réunion reste lisible après un crash.
/// L'en-tête suit l'audio écrit sans attendre la fermeture, et un WAV dont
/// l'en-tête n'a jamais été finalisé se répare d'après la taille du fichier.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('oats_wav_crash_');
  });

  tearDown(() => temp.delete(recursive: true));

  int dataSize(Uint8List wav) =>
      ByteData.sublistView(wav, 0, 44).getUint32(40, Endian.little);
  int riffSize(Uint8List wav) =>
      ByteData.sublistView(wav, 0, 44).getUint32(4, Endian.little);

  /// Fichier tel qu'un crash le laisse : en-tête aux tailles nulles.
  Future<File> unfinishedWav(int pcmBytes) async {
    final File file = File('${temp.path}/crashed.wav');
    final WavRecorder recorder = WavRecorder();
    await recorder.open(file.path);
    final Uint8List header = (await file.readAsBytes()).sublist(0, 44);
    await recorder.close();
    final Uint8List pcm = Uint8List(pcmBytes)
      ..fillRange(0, pcmBytes, 7);
    await file.writeAsBytes(<int>[...header, ...pcm], flush: true);
    return file;
  }

  test(
    'l en-tête couvre l audio déjà écrit, sans attendre la fermeture',
    () async {
      final File file = File('${temp.path}/live.wav');
      final WavRecorder recorder = WavRecorder();
      await recorder.open(file.path);

      const int chunkBytes = 3200; // 100 ms
      for (int i = 0; i < 30; i++) {
        await recorder.append(Uint8List(chunkBytes));
      }

      final Uint8List onDisk = await file.readAsBytes();
      const int written = 30 * chunkBytes; // 3 s
      expect(
        dataSize(onDisk),
        inInclusiveRange(written - 32000, written),
        reason: 'au plus 1 s d audio hors en-tête',
      );
      expect(riffSize(onDisk), 36 + dataSize(onDisk));
      await recorder.close();
    },
  );

  test('répare un WAV non finalisé d après la taille du fichier', () async {
    final File file = await unfinishedWav(32000);

    await WavRecorder.repair(file.path);

    final Uint8List wav = await file.readAsBytes();
    expect(wav.length, 44 + 32000);
    expect(dataSize(wav), 32000);
    expect(riffSize(wav), 36 + 32000);
    expect(wav.sublist(44).every((int b) => b == 7), isTrue);
  });

  test('ignore un demi-échantillon laissé en fin de fichier', () async {
    final File file = await unfinishedWav(32001);

    await WavRecorder.repair(file.path);

    final Uint8List wav = await file.readAsBytes();
    expect(dataSize(wav), 32000);
    expect(riffSize(wav), 36 + dataSize(wav));
  });

  test('laisse intact un WAV déjà finalisé', () async {
    final File file = File('${temp.path}/ok.wav');
    final WavRecorder recorder = WavRecorder();
    await recorder.open(file.path);
    await recorder.append(Uint8List(6400)..fillRange(0, 6400, 3));
    await recorder.close();
    final Uint8List before = await file.readAsBytes();

    await WavRecorder.repair(file.path);

    expect(await file.readAsBytes(), before);
  });

  test('ne casse pas un fichier plus court qu un en-tête', () async {
    final File file = File('${temp.path}/tiny.wav');
    await file.writeAsBytes(<int>[1, 2, 3]);

    await WavRecorder.repair(file.path);

    expect(await file.readAsBytes(), <int>[1, 2, 3]);
  });
}
