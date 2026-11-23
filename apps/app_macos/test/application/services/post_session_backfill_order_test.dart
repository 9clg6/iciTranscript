import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/voiced_pcm.dart';

/// Tour 5, suite (a) : ordre après la réunion. La passe post-session
/// (diarization, lancée par le view model après `stopTranscription()`)
/// supprime les WAV de la session et arrête le serveur. Le rattrapage des
/// repères doit donc être fini quand `stopTranscription()` rend la main :
/// tout ce qui suit peut supprimer les WAV sans perdre le rattrapage.
///
/// Temps réel (le rattrapage lit un vrai WAV), dossier temporaire de test.
void main() {
  late Directory recordings;

  setUp(() async {
    final String dir = LiveTranscriptionService.recordingsDir;
    expect(dir, startsWith(Directory.systemTemp.path));
    expect(dir, isNot(contains('/Library/Application Support/')));
    recordings = Directory(dir);
    await recordings.create(recursive: true);
  });

  test('le rattrapage est fini quand l arrêt rend la main, avant toute '
      'suppression des WAV', () async {
    final InMemorySessionRepository sessions = InMemorySessionRepository();
    final InMemoryTranscriptRepository segments =
        InMemoryTranscriptRepository();
    final FakeTranscriptionRemoteDataSource remote =
        FakeTranscriptionRemoteDataSource();
    final TranscriptionService transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: segments,
      ),
    );
    final _WavCheckingTranscriber transcriber = _WavCheckingTranscriber();
    final LiveTranscriptionService service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(
        channel: FakeProcessManagerChannel(),
      ),
      audioCaptureChannel: FakeAudioCaptureChannel(),
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      createWavRecorder: FakeWavRecorder.new,
      gapBackfill: GapBackfillService(
        transcriber: transcriber,
        transcripts: segments,
        isRecording: () => transcription.isTranscribingStream.value,
      ),
    );

    await service.startTranscription(
      serverCommand: 'uvx',
      serverArgs: const <String>['voxmlx-serve'],
    );
    final String id = transcription.currentSessionStream.value!.id;
    final int t0 = transcription
        .currentSessionStream
        .value!
        .createdAt
        .millisecondsSinceEpoch;
    remote.emitGap(
      AudioGap(
        source: AudioSource.input,
        startMs: t0 + 10000,
        endMs: t0 + 20000,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      segments.of(AudioSource.input).single.text,
      startsWith('Transcription interrompue'),
    );

    final File mic = File('${recordings.path}/${id}_mic.wav');
    final WavRecorder recorder = WavRecorder();
    await recorder.open(mic.path);
    await recorder.append(voicedPcm(30 * 32000));
    await recorder.close();
    transcriber.wav = mic;

    await service.stopTranscription();
    await mic.delete(); // la passe post-session supprime les WAV
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(transcriber.sawWav, <bool>[true]);
    expect(segments.of(AudioSource.input).map((s) => s.text), <String>[
      'Retrouvé.',
    ]);
  });
}

/// Note si le WAV existait encore au moment de la retranscription.
final class _WavCheckingTranscriber implements PcmTranscriber {
  File? wav;
  final List<bool> sawWav = <bool>[];

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    sawWav.add(wav?.existsSync() ?? false);
    return <({int offsetMs, String text})>[(offsetMs: 0, text: 'Retrouvé.')];
  }
}
