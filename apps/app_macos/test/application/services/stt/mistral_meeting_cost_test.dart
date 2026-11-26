import 'dart:async';

import 'package:core_data/clients/engine_routing_client.dart';
import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/mistral_fakes.dart';

// Prix de la transcription en ligne (2026-11-26) : à l'arrêt d'une réunion
// transcrite par Mistral, l'audio temps réel réellement envoyé par les DEUX
// sockets (micro + son du Mac, maintien compris) est rangé dans la note.
// Une réunion sur le moteur local ne range rien. La réunion suivante repart
// de zéro. Montage comme les providers : chaque socket est un
// EngineRoutingClient (voxmlx local | MistralRealtimeClient) ; seuls les
// serveurs sont faux (aucun réseau).
//
// API supposée :
// - `LiveTranscriptionService({..., SessionRepository? sessions})` ;
// - à l'arrêt, après la déconnexion : `remote.takeSentAudioMs()` (somme des
//   deux sockets, voir core_data mistral_realtime_usage_test.dart) ; si > 0,
//   `sessions.addCloudUsage(idDeLaNote, realtimeMs: ms)` ;
// - le compte est lu (donc remis à zéro) à chaque arrêt.
// Limite assumée : app tuée en pleine réunion → rien de compté.
const String _key = 'mistral-test-SECRET-0123456789';

final class _Meeting {
  _Meeting(this.async) {
    WebSocketClient socket(FakeMistralServer server) => EngineRoutingClient(
      local: local.transport(const <String, String>{}),
      mistral: MistralRealtimeClient(
        apiKey: () async => _key,
        transport: server.transport,
      ),
    );
    final TranscriptionService transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: segments,
      ),
    );
    service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(channel: process),
      audioCaptureChannel: audio,
      transcriptionRemoteDataSource: TranscriptionRemoteDataSourceImpl(
        micClient: socket(mic),
        systemClient: socket(system),
      ),
      transcriptionService: transcription,
      createWavRecorder: FakeWavRecorder.new,
      sessions: sessions,
    );
  }

  final FakeAsync async;
  final FakeMistralServer mic = FakeMistralServer();
  final FakeMistralServer system = FakeMistralServer();

  /// Le « serveur local » (voxmlx) : n'est jamais Mistral.
  final FakeMistralServer local = FakeMistralServer();
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  final InMemoryTranscriptRepository segments = InMemoryTranscriptRepository();
  late final LiveTranscriptionService service;
  int _id = 0;

  /// Audio Mistral reçu par les deux faux serveurs (l'oracle).
  int get wireMs => mic.appendedMs + system.appendedMs;

  String get sessionId => service.currentSessionStream.value!.id;

  void start(TranscriptionEngine engine) {
    unawaited(
      service
          .startTranscription(
            outputEnabled: true,
            serverCommand: LiveServiceHarness.command,
            serverArgs: LiveServiceHarness.args,
            engine: engine,
          )
          .catchError((Object _) {}),
    );
    async.elapse(const Duration(seconds: 1));
  }

  /// [count] × 100 ms de parole au micro, et du Mac pendant [systemCount].
  void talk(int count, {int systemCount = 0}) {
    final int t0 =
        service.currentSessionStream.value!.createdAt.millisecondsSinceEpoch;
    for (int i = 0; i < count; i++) {
      final int id = _id++;
      audio.emit(chunk(AudioSource.input, id, timestampMs: t0 + id * 100));
      if (i < systemCount) {
        audio.emit(chunk(AudioSource.output, id, timestampMs: t0 + id * 100));
      }
      async.elapse(const Duration(milliseconds: 100));
    }
  }

  /// [count] × 100 ms de silence (le maintien part toutes les 4 s).
  void quiet(int count) {
    final int t0 =
        service.currentSessionStream.value!.createdAt.millisecondsSinceEpoch;
    for (int i = 0; i < count; i++) {
      final int id = _id++;
      audio.emit(
        chunk(AudioSource.input, id, timestampMs: t0 + id * 100, voiced: false),
      );
      async.elapse(const Duration(milliseconds: 100));
    }
  }

  /// Arrêt, puis assez de temps pour l'attente de fin (bornée à 120 s).
  void stop() {
    unawaited(service.stopTranscription());
    async.elapse(const Duration(minutes: 3));
  }
}

void main() {
  test('arrêt d une réunion Mistral : la note garde l audio temps réel des '
      'deux sources, tel qu envoyé (pause et maintien compris)', () {
    fakeAsync((FakeAsync async) {
      final _Meeting m = _Meeting(async);
      m.start(TranscriptionEngine.mistral);
      final String id = m.sessionId;

      m.talk(50, systemCount: 30);
      m.quiet(120); // 12 s de pause : du silence de maintien part
      m.talk(20);
      m.stop();

      expect(m.sessions.store[id]?.status, SessionStatus.completed);
      expect(m.mic.appendedMs, greaterThan(0), reason: 'micro envoyé');
      expect(m.system.appendedMs, greaterThan(0), reason: 'Mac envoyé');
      expect(m.sessions.cloudUsage[id]?.realtimeMs, m.wireMs);
      expect(m.sessions.cloudUsage[id]?.batchMs ?? 0, 0);
    });
  });

  test('réunion sur le moteur local : rien de rangé, rien chez Mistral', () {
    fakeAsync((FakeAsync async) {
      final _Meeting m = _Meeting(async);
      m.start(TranscriptionEngine.local);
      final String id = m.sessionId;

      m.talk(50, systemCount: 30);
      m.stop();

      expect(m.sessions.store[id]?.status, SessionStatus.completed);
      expect(m.wireMs, 0, reason: 'aucun audio chez Mistral');
      expect(m.sessions.cloudUsage[id], isNull);
    });
  });

  test('deux réunions de suite : chacune garde son propre audio (la seconde '
      'repart de zéro)', () {
    fakeAsync((FakeAsync async) {
      final _Meeting m = _Meeting(async);
      m.start(TranscriptionEngine.mistral);
      final String first = m.sessionId;
      m.talk(40, systemCount: 40);
      m.stop();
      final int firstWire = m.wireMs;

      async.elapse(const Duration(minutes: 1));
      m.start(TranscriptionEngine.mistral);
      final String second = m.sessionId;
      expect(second, isNot(first));
      m.talk(15);
      m.stop();

      expect(firstWire, greaterThan(0));
      expect(m.sessions.cloudUsage[first]?.realtimeMs, firstWire);
      expect(m.sessions.cloudUsage[second]?.realtimeMs, m.wireMs - firstWire);
      expect(m.wireMs - firstWire, greaterThan(0));
    });
  });
}
