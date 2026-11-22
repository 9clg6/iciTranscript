import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/core/providers/services/transcription.service.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcription_server_arbiter.provider.g.dart';

/// Arbitre unique du serveur de transcription : enregistrement > dictée >
/// rattrapage des pertes.
@Riverpod(keepAlive: true)
TranscriptionServerArbiter transcriptionServerArbiter(Ref ref) {
  final TranscriptionService transcription = ref.watch(
    transcriptionServiceProvider,
  );
  return TranscriptionServerArbiter(
    isRecording: () => transcription.isTranscribingStream.value,
  );
}
