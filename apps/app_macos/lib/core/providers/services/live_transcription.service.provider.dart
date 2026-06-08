import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/providers/data/datasource/transcription.remote.data_source.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/transcription.service.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_transcription.service.provider.g.dart';

/// Provider singleton pour [LiveTranscriptionService].
///
/// Orchestre la transcription en direct en coordonnant :
/// - Le serveur ML via [ProcessManagerService]
/// - La capture audio via [AudioCaptureChannel]
/// - Le WebSocket via [TranscriptionRemoteDataSource]
/// - La session et les segments via [TranscriptionService]
@Riverpod(keepAlive: true)
LiveTranscriptionService liveTranscriptionService(Ref ref) {
  final ProcessManagerService processManagerService = ref.watch(
    processManagerServiceProvider,
  );
  final AudioCaptureChannel audioCaptureChannel = ref.watch(
    audioCaptureChannelProvider,
  );
  final TranscriptionRemoteDataSource transcriptionRemoteDataSource = ref.watch(
    transcriptionRemoteDataSourceProvider,
  );
  final TranscriptionService transcriptionService = ref.watch(
    transcriptionServiceProvider,
  );

  final LiveTranscriptionService service = LiveTranscriptionService(
    processManagerService: processManagerService,
    audioCaptureChannel: audioCaptureChannel,
    transcriptionRemoteDataSource: transcriptionRemoteDataSource,
    transcriptionService: transcriptionService,
  );

  ref.onDispose(service.dispose);
  return service;
}
