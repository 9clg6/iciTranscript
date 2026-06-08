import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcription.remote.data_source.provider.g.dart';

/// Provider pour [TranscriptionRemoteDataSource].
///
/// Fournit l'implementation WebSocket pour la communication
/// avec le serveur voxmlx-serve (transcription en temps reel).
@riverpod
TranscriptionRemoteDataSource transcriptionRemoteDataSource(Ref ref) {
  final WebSocketClient webSocketClient = WebSocketClient();
  ref.onDispose(webSocketClient.dispose);
  return TranscriptionRemoteDataSourceImpl(webSocketClient: webSocketClient);
}
