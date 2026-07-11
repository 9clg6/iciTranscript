import 'dart:async';
import 'dart:io';

import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('le micro natif émet environ 10 chunks de 100 ms par seconde', (
    WidgetTester tester,
  ) async {
    final AudioCaptureChannel channel = AudioCaptureChannel();
    final int measurementSeconds =
        int.tryParse(
          Platform.environment['AUDIO_CAPTURE_TEST_SECONDS'] ?? '',
        ) ??
        6;
    int inputChunks = 0;
    final StreamSubscription<AudioChunk> subscription = channel.audioStream
        .where((AudioChunk chunk) => chunk.source == AudioSource.input)
        .listen((AudioChunk _) => inputChunks++);

    await channel.startCapture(outputEnabled: false);
    // Exclure l'initialisation et l'arrêt natifs : on mesure uniquement la
    // fenêtre de capture stable, puis on remet le compteur à zéro.
    inputChunks = 0;
    final Stopwatch elapsed = Stopwatch()..start();
    await Future<void>.delayed(Duration(seconds: measurementSeconds));
    elapsed.stop();
    await channel.stopCapture();
    await subscription.cancel();
    await channel.dispose();

    final double chunksPerSecond =
        inputChunks / (elapsed.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print(
      'DÉBIT MICRO: ${chunksPerSecond.toStringAsFixed(3)} chunks/s '
      'sur ${elapsed.elapsedMilliseconds} ms',
    );
    expect(
      chunksPerSecond,
      inInclusiveRange(8.5, 11.5),
      reason:
          'Un débit supérieur accélère artificiellement le micro et crée '
          'un backlog côté transcription.',
    );
  });
}
