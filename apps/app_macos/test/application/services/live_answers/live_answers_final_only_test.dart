import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../../helpers/live_answers_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Seule la parole FINALE en direct alimente la porte et le contexte (T4) :
/// formes réelles de main. Repère de perte = segment sauvé par
/// `saveSegment` dont le texte commence par
/// `LiveTranscriptionService.gapMarkerPrefix` ; texte retrouvé après la
/// réunion = écrit par `GapBackfillService` directement dans le dépôt.
///
/// API supposée : `LiveTranscriptionService.finalizedSegmentsStream`
/// (`Stream<TranscriptSegmentEntity>`), n'émet ni repère de perte, ni
/// provisoire, ni texte retrouvé plus tard.
void main() {
  test('un repère de perte n\'est pas émis comme phrase finale', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
      live.service.finalizedSegmentsStream.listen(finals.add);

      live.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: live.t0 + 10000,
          endMs: live.t0 + 20000,
        ),
      );
      async.elapse(const Duration(seconds: 1));

      expect(
        live.segments.of(AudioSource.output).single.text,
        startsWith(LiveTranscriptionService.gapMarkerPrefix),
        reason: 'le repère est bien sauvé dans la note',
      );
      expect(finals, isEmpty);
    });
  });

  test('une phrase sauvée en provisoire puis finalisée sort une seule fois, '
      'avec son texte final', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async)..start();
      final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
      live.service.finalizedSegmentsStream.listen(finals.add);

      live.fakeRemote.emitDelta(AudioSource.output, 'Quand est-ce que vous');
      // Point de sauvegarde provisoire passé (2 s), plusieurs fois.
      async.elapse(const Duration(seconds: 7));
      live.fakeRemote.emitDelta(AudioSource.output, ' livrez');
      async.elapse(const Duration(seconds: 7));
      live.fakeRemote.emitDone(
        AudioSource.output,
        'Quand est-ce que vous livrez le lot 1 ?',
      );
      async.elapse(const Duration(seconds: 1));

      expect(finals.map((TranscriptSegmentEntity s) => s.text), <String>[
        'Quand est-ce que vous livrez le lot 1 ?',
      ]);
    });
  });

  test('le texte retrouvé après la réunion (rattrapage des pertes) ne '
      'déclenche rien', () async {
    final Directory recordings = Directory(
      LiveTranscriptionService.recordingsDir,
    );
    expect(recordings.path, startsWith(Directory.systemTemp.path));
    await recordings.create(recursive: true);

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
    final LiveTranscriptionService service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(
        channel: FakeProcessManagerChannel(),
      ),
      audioCaptureChannel: FakeAudioCaptureChannel(),
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      createWavRecorder: FakeWavRecorder.new,
      gapBackfill: GapBackfillService(
        transcriber: _Recovered(),
        transcripts: segments,
        isRecording: () => transcription.isTranscribingStream.value,
      ),
    );
    final LiveAnswersHarness answers = LiveAnswersHarness();
    final List<TranscriptSegmentEntity> finals = <TranscriptSegmentEntity>[];
    service.finalizedSegmentsStream.listen((TranscriptSegmentEntity s) {
      finals.add(s);
      answers.service.onSegmentFinalized(s.copyWith(sessionId: 's1'));
    });

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
        source: AudioSource.output,
        startMs: t0 + 10000,
        endMs: t0 + 20000,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final File wav = File('${recordings.path}/${id}_system.wav');
    final WavRecorder recorder = WavRecorder();
    await recorder.open(wav.path);
    await recorder.append(Uint8List(30 * 32000));
    await recorder.close();
    addTearDown(() async {
      if (wav.existsSync()) await wav.delete();
    });

    await service.stopTranscription();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      segments.of(AudioSource.output).map((TranscriptSegmentEntity s) {
        return s.text;
      }),
      contains(_Recovered.text),
      reason: 'le rattrapage a bien écrit le texte retrouvé',
    );
    expect(finals, isEmpty);
    expect(answers.questions, isEmpty);
    expect(answers.llm.requests, isEmpty);
  });
}

/// Retrouve une question dans l'audio perdu.
final class _Recovered implements PcmTranscriber {
  static const String text = 'Est-ce que vous livrez le lot 1 en mars ?';

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      <({int offsetMs, String text})>[(offsetMs: 0, text: text)];
}
