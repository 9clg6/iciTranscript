import 'package:core_data/repositories/audio.repository.impl.dart';
import 'package:core_domain/domain/repositories/audio.repository.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'audio.repository.provider.g.dart';

/// Provider pour [AudioRepository].
///
/// Fournit l'implementation [AudioRepositoryImpl] qui delegue les appels
/// au [AudioCaptureChannel] (Platform Channel Swift) pour la capture audio.
@riverpod
AudioRepository audioRepository(Ref ref) {
  final AudioCaptureChannel channel = ref.watch(audioCaptureChannelProvider);
  return AudioRepositoryImpl(
    startCaptureHandler:
        ({required String inputDeviceId, required String outputDeviceId}) =>
            channel.startCapture(
              inputDeviceId: inputDeviceId,
              outputEnabled: true,
            ),
    stopCaptureHandler: channel.stopCapture,
    audioStreamHandler: channel.audioStream.map(
      (dynamic chunk) => AudioChunk(source: chunk.source, data: chunk.data),
    ),
    listDevicesHandler: channel.listDevices,
    isSystemAudioAvailableHandler: channel.isSystemAudioAvailable,
  );
}
