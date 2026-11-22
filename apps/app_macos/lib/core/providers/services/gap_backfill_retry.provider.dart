import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/transcription.service.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_backfill_retry.provider.g.dart';

/// Rattrapage des repères depuis les WAV, avec reprise quand le serveur de
/// transcription revient (une seule instance : un seul fichier d'attente).
@Riverpod(keepAlive: true)
GapBackfillRetry gapBackfillRetry(Ref ref) {
  final TranscriptionService transcription = ref.watch(
    transcriptionServiceProvider,
  );
  bool isRecording() => transcription.isTranscribingStream.value;
  final GapBackfillRetry retry = GapBackfillRetry(
    backfill: GapBackfillService(
      transcriber: WebSocketPcmTranscriber(
        url: ref
            .watch(launchServerPortsProvider)
            .transcriptionWebSocket
            .toString(),
      ),
      transcripts: ref.watch(transcriptRepositoryProvider),
      isRecording: isRecording,
    ),
    serverStates: ref.watch(processManagerServiceProvider).stateStream,
    isRecording: isRecording,
    recordingsDirectory: LiveTranscriptionService.recordingsDir,
  );
  ref.onDispose(retry.dispose);
  return retry;
}
