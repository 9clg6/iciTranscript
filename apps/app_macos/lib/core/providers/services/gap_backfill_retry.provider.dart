import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/stt/mistral_batch_transcriber.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/transcription_server_arbiter.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_backfill_retry.provider.g.dart';

/// Rattrapage des repères depuis les WAV, avec reprise quand le serveur de
/// transcription revient (une seule instance : un seul fichier d'attente).
@Riverpod(keepAlive: true)
GapBackfillRetry gapBackfillRetry(Ref ref) {
  final TranscriptionServerArbiter arbiter = ref.watch(
    transcriptionServerArbiterProvider,
  );
  // Enregistrement ou dictée : le rattrapage cède le serveur (séquentiel).
  bool mustYield() => arbiter.backfillMustYield;
  final ApiKeyStore keys = ref.watch(apiKeyStoreProvider);
  final GapBackfillRetry retry = GapBackfillRetry(
    backfill: GapBackfillService(
      // Le moteur choisi AU MOMENT du rattrapage (pas celui de la note) :
      // voxmlx sur ce Mac, ou l'API batch de Mistral. Une ancienne note
      // locale part chez Mistral après un changement de moteur.
      transcriber: EngineTranscriber(
        local: WebSocketPcmTranscriber(
          url: ref
              .watch(launchServerPortsProvider)
              .transcriptionWebSocket
              .toString(),
          // Vrai dès qu'un démarrage est demandé (LiveTranscriptionService)
          // ou qu'une dictée commence : aucun morceau ne part ensuite.
          shouldYield: mustYield,
        ),
        cloud: MistralBatchTranscriber(
          dio: ref.watch(llmDioProvider),
          apiKey: () => keys.read(LlmProviderId.mistral),
        ),
        engine: () async => TranscriptionEngineSelection(
          keys,
        ).fromPrefs(await ref.read(prefsStoreProvider).read()),
      ),
      transcripts: ref.watch(transcriptRepositoryProvider),
      isRecording: mustYield,
      dictatedIntervals: DictatedIntervalsStore(
        LiveTranscriptionService.recordingsDir,
      ),
    ),
    serverStates: ref.watch(processManagerServiceProvider).stateStream,
    isRecording: mustYield,
    recordingsDirectory: LiveTranscriptionService.recordingsDir,
    resumeSignals: arbiter.backfillMayResume,
  );
  ref.onDispose(retry.dispose);
  return retry;
}
