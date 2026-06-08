import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'audio_capture.provider.g.dart';

/// Provider singleton pour [AudioCaptureChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la capture audio
/// (microphone et audio systeme via ScreenCaptureKit).
@Riverpod(keepAlive: true)
AudioCaptureChannel audioCaptureChannel(Ref ref) {
  final AudioCaptureChannel channel = AudioCaptureChannel();
  ref.onDispose(channel.dispose);
  return channel;
}
