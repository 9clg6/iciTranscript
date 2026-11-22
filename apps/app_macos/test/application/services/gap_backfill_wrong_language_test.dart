import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 6, point 4c : la même phrase, encore en mauvaise langue (ou en
// écriture non latine) après le rattrapage, garde son repère ; elle n'est
// pas acceptée la seconde fois. Une telle tentative a atteint le serveur :
// elle compte (3 au plus).
void main() {
  const String sessionId = '1700000000000';
  late Directory dir;
  late InMemoryTranscriptRepository repo;
  late _Reply transcriber;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('oats_lang_backfill_');
    repo = InMemoryTranscriptRepository();
    transcriber = _Reply();
    final WavRecorder recorder = WavRecorder();
    await recorder.open('${dir.path}/${sessionId}_mic.wav');
    await recorder.append(Uint8List(30 * 32000));
    await recorder.close();
    await repo.save(
      TranscriptSegmentEntity(
        id: 'm',
        sessionId: sessionId,
        source: AudioSource.input,
        text: LiveTranscriptionService.gapMarkerText(10000, 20000),
        timestampMs: 10000,
        createdAt: DateTime(2026, 11, 22, 10),
      ),
    );
  });

  tearDown(() => dir.delete(recursive: true));

  GapBackfillService service() => GapBackfillService(
    transcriber: transcriber,
    transcripts: repo,
    isRecording: () => false,
  );

  List<String> texts() => repo
      .of(AudioSource.input)
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  for (final String wrong in <String>[
    'El equipo ha terminado el presupuesto para el próximo trimestre.',
    'नमस्ते आप सब कैसे हैं आज',
  ]) {
    test('« $wrong » n est pas accepté : le repère reste', () async {
      transcriber.text = wrong;

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(texts(), hasLength(1));
      expect(texts().single, startsWith('Transcription interrompue'));
    });
  }

  test('toujours en mauvaise langue : 3 tentatives au plus', () async {
    transcriber.text =
        'Vamos a revisar los resultados de la reunión mañana por la tarde.';
    final StreamController<ServerState> states =
        StreamController<ServerState>.broadcast();
    final GapBackfillRetry retry = GapBackfillRetry(
      backfill: service(),
      serverStates: states.stream,
      isRecording: () => false,
      recordingsDirectory: dir.path,
    );
    await retry.afterSession(sessionId);
    for (int i = 0; i < 4; i++) {
      states.add(ServerState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await retry.dispose();
    await states.close();

    expect(transcriber.calls, 3);
    expect(texts().single, startsWith('Transcription interrompue'));
  });
}

final class _Reply implements PcmTranscriber {
  String text = '';
  int calls = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    return <({int offsetMs, String text})>[(offsetMs: 0, text: text)];
  }
}
