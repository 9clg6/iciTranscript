import 'dart:async';

import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../helpers/live_service_fakes.dart';

/// La WebSocket de transcription se connecte au port où le serveur a été
/// lancé : 8000 en release, 8100 sur données de dev. L'URL dérive des ports
/// du lancement ; l'appelant n'a pas à la connaître (la vue ne la passe pas).
void main() {
  for (final (AppBuildMode mode, String url) in <(AppBuildMode, String)>[
    (AppBuildMode.release, 'ws://127.0.0.1:8000/v1/realtime'),
    (AppBuildMode.debug, 'ws://127.0.0.1:8100/v1/realtime'),
  ]) {
    test('${mode.name} : la WebSocket vise $url', () {
      fakeAsync((FakeAsync async) {
        final InMemorySessionRepository sessions = InMemorySessionRepository();
        final FakeTranscriptionRemoteDataSource remote =
            FakeTranscriptionRemoteDataSource();
        final LiveTranscriptionService service = LiveTranscriptionService(
          processManagerService: ProcessManagerService(
            channel: FakeProcessManagerChannel(),
          ),
          audioCaptureChannel: FakeAudioCaptureChannel(),
          transcriptionRemoteDataSource: remote,
          transcriptionService: TranscriptionService(
            startSessionUseCase: StartSessionUseCase(
              sessionRepository: sessions,
            ),
            stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
            saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
              transcriptRepository: InMemoryTranscriptRepository(),
            ),
          ),
          createWavRecorder: FakeWavRecorder.new,
          ports: resolveServerPorts(const <String, String>{
            'HOME': '/Users/someone',
          }, buildMode: mode),
        );

        // Comme la vue : commande et arguments, pas d'URL.
        unawaited(
          service.startTranscription(
            serverCommand: 'uvx',
            serverArgs: const <String>['voxmlx-serve', '--model', 'm'],
          ),
        );
        async.elapse(const Duration(seconds: 1));

        expect(remote.connectedUrls, <String>[url]);

        unawaited(service.stopTranscription());
        async.elapse(const Duration(seconds: 10));
      });
    });
  }
}
