import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 6, point 1 (sonde 4) : après la réunion B, les repères en attente de
// la réunion A ne repartaient que sur un signal « serveur prêt » ou au
// lancement suivant. Les sessions en attente sont réessayées dès que le
// serveur est disponible et que rien de prioritaire ne tourne, en
// particulier juste après la fin d'un enregistrement (sa propre
// finalisation et son rattrapage faits) ; une session à la fois, la plus
// ancienne d'abord. Temps réel, dossiers temporaires, aucun réseau.
void main() {
  group('relance après une session (GapBackfillRetry)', () {
    late Directory dir;
    late InMemoryTranscriptRepository repo;
    late _Transcriber transcriber;
    late StreamController<ServerState> states;
    late GapBackfillRetry retry;

    const String a = '1700000000000';
    const String c = '1700000500000';
    const String b = '1700001000000';

    Future<void> sessionWithMarker(String id, int base) async {
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${id}_mic.wav');
      for (int k = 0; k < 300; k++) {
        final Uint8List data = Uint8List(3200);
        ByteData.sublistView(data).setInt16(0, base + k, Endian.little);
        await recorder.append(data);
      }
      await recorder.close();
      await repo.save(
        TranscriptSegmentEntity(
          id: '$id-m',
          sessionId: id,
          source: AudioSource.input,
          text: LiveTranscriptionService.gapMarkerText(10000, 20000),
          timestampMs: 10000,
          createdAt: DateTime(2026, 11, 22, 10),
        ),
      );
    }

    bool marked(String id) => repo.store.values.any(
      (TranscriptSegmentEntity s) =>
          s.sessionId == id && s.text.startsWith('Transcription interrompue'),
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_resume_');
      repo = InMemoryTranscriptRepository();
      transcriber = _Transcriber();
      states = StreamController<ServerState>.broadcast();
      retry = GapBackfillRetry(
        backfill: GapBackfillService(
          transcriber: transcriber,
          transcripts: repo,
          isRecording: () => false,
        ),
        serverStates: states.stream,
        isRecording: () => false,
        recordingsDirectory: dir.path,
      );
      await sessionWithMarker(c, 2000); // créée en premier, mais plus récente
      await sessionWithMarker(a, 1000);
    });

    tearDown(() async {
      await retry.dispose();
      await states.close();
      await dir.delete(recursive: true);
    });

    test('la fin d une autre session relance les sessions en attente, une '
        'à la fois, la plus ancienne d abord', () async {
      transcriber.available = false;
      await retry.afterSession(c);
      await retry.afterSession(a);
      expect(marked(a), isTrue);
      expect(marked(c), isTrue);
      transcriber
        ..available = true
        ..calls.clear();

      await retry.afterSession(b); // B : aucun repère, aucun WAV
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(transcriber.calls, <int>[1000, 2000], reason: 'A puis C');
      expect(transcriber.maxConcurrent, 1);
      expect(marked(a), isFalse);
      expect(marked(c), isFalse);
    });
  });

  test('service : après la réunion B sans repère, le repère en attente de '
      'A est rattrapé sans signal « serveur prêt »', () async {
    final String recordings = LiveTranscriptionService.recordingsDir;
    expect(recordings, startsWith(Directory.systemTemp.path));
    final Directory rec = Directory(recordings);
    if (rec.existsSync()) await rec.delete(recursive: true);
    await rec.create(recursive: true);

    final InMemorySessionRepository sessions = InMemorySessionRepository();
    final InMemoryTranscriptRepository segments =
        InMemoryTranscriptRepository();
    final FakeTranscriptionRemoteDataSource remote =
        FakeTranscriptionRemoteDataSource();
    final FakeProcessManagerChannel process = FakeProcessManagerChannel();
    final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
    final TranscriptionService transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: segments,
      ),
    );
    bool recording() => transcription.isTranscribingStream.value;
    final _Transcriber transcriber = _Transcriber()..available = false;
    final GapBackfillRetry retry = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: transcriber,
        transcripts: segments,
        isRecording: recording,
      ),
      serverStates: process.stateStream,
      isRecording: recording,
      recordingsDirectory: recordings,
    );
    addTearDown(retry.dispose);
    final LiveTranscriptionService service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(channel: process),
      audioCaptureChannel: audio,
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      gapBackfillRetry: retry,
    );
    addTearDown(service.dispose);
    Future<void> start() => service.startTranscription(
      serverCommand: 'uvx',
      serverArgs: const <String>['voxmlx-serve'],
    );

    // Réunion A : une perte, serveur de rattrapage absent à son arrêt.
    await start();
    final String a = transcription.currentSessionStream.value!.id;
    final int t0 = transcription
        .currentSessionStream
        .value!
        .createdAt
        .millisecondsSinceEpoch;
    for (int id = 0; id < 300; id++) {
      audio.emit(chunk(AudioSource.input, id, timestampMs: t0 + id * 100));
      if (id % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    remote.emitGap(
      AudioGap(
        source: AudioSource.input,
        startMs: t0 + 10000,
        endMs: t0 + 20000,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await service.stopTranscription();
    bool markedA() => segments.store.values.any(
      (TranscriptSegmentEntity s) =>
          s.sessionId == a && s.text.startsWith('Transcription interrompue'),
    );
    expect(markedA(), isTrue);

    // Réunion B, sans perte ; le serveur est revenu entre-temps, sans
    // nouveau signal « prêt » (il tournait déjà).
    transcriber.available = true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await service.stopTranscription();
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(markedA(), isFalse, reason: 'A rattrapée après B');
  });
}

/// Retient le premier échantillon de chaque PCM reçu (numéro de session).
final class _Transcriber implements PcmTranscriber {
  bool available = true;
  final List<int> calls = <int>[];
  int _running = 0;
  int maxConcurrent = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    _running++;
    if (_running > maxConcurrent) maxConcurrent = _running;
    try {
      calls.add(ByteData.sublistView(pcm).getInt16(0, Endian.little) - 90);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!available) {
        throw const TranscriberUnavailable('connexion refusée');
      }
      return <({int offsetMs, String text})>[(offsetMs: 0, text: 'Retrouvé.')];
    } finally {
      _running--;
    }
  }
}
