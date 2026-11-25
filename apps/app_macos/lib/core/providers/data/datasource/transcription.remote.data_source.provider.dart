import 'package:core_data/clients/engine_routing_client.dart';
import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcription.remote.data_source.provider.g.dart';

/// Provider pour [TranscriptionRemoteDataSource].
///
/// Deux flux (micro + système), chacun routé vers voxmlx-serve sur ce Mac
/// ou vers Mistral en ligne selon l'adresse que passe le service (moteur
/// choisi) ; la couche de fiabilité est la même.
@riverpod
TranscriptionRemoteDataSource transcriptionRemoteDataSource(Ref ref) {
  final ApiKeyStore keys = ref.watch(apiKeyStoreProvider);
  WebSocketClient socket() => EngineRoutingClient(
    local: WebSocketClient(),
    mistral: MistralRealtimeClient(
      apiKey: () => keys.read(LlmProviderId.mistral),
      transport: MistralRealtimeClient.defaultTransport,
    ),
  );
  final TranscriptionRemoteDataSourceImpl ds =
      TranscriptionRemoteDataSourceImpl(
        micClient: socket(),
        systemClient: socket(),
      );
  ref.onDispose(ds.dispose);
  return ds;
}
