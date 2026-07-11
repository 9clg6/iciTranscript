import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

void main() {
  test(
    'close attend les append concurrents et écrit un WAV cohérent',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'ici_wav_recorder_test_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File output = File('${temp.path}/meeting.wav');
      final WavRecorder recorder = WavRecorder();
      await recorder.open(output.path);

      const int chunkCount = 100;
      const int chunkBytes = 3200;
      for (int index = 0; index < chunkCount; index++) {
        recorder.append(Uint8List(chunkBytes)..fillRange(0, chunkBytes, index));
      }
      await recorder.close();

      final Uint8List wav = await output.readAsBytes();
      final ByteData header = ByteData.sublistView(wav, 0, 44);
      expect(wav.length, 44 + chunkCount * chunkBytes);
      expect(header.getUint32(40, Endian.little), chunkCount * chunkBytes);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(wav[44], 0);
      expect(wav[44 + 50 * chunkBytes], 50);
      expect(wav.last, 99);
    },
  );
}
