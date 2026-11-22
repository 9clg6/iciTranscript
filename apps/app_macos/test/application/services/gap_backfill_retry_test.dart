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

// Tour 5 bis, point 2 : serveur de transcription indisponible au moment du
// rattrapage. Le repère reste, et la session est réessayée plus tard : dès
// que le serveur est prêt hors enregistrement, et au lancement suivant ;
// au plus 3 tentatives par session, puis le repère reste ; une session dont
// le WAV a disparu n'est plus réessayée.
//
// API supposée (lib/application/services/gap_backfill_retry.dart) :
// `GapBackfillRetry({required GapBackfillService backfill, required
// Stream<ServerState> serverStates, required bool Function() isRecording,
// required String recordingsDirectory})`, `static const int maxAttempts`
// (3), `Future<void> afterSession(String sessionId)` (première tentative),
// `Future<void> retryPending()` (au lancement), `Future<void> dispose()`.
// Les sessions en attente survivent au relancement (gardées sous
// recordingsDirectory, format libre).
void main() {
  const String sessionId = '1700000000000';
  late Directory dir;
  late InMemoryTranscriptRepository repo;
  late _Transcriber transcriber;
  late StreamController<ServerState> states;
  late bool recording;
  final List<GapBackfillRetry> retries = <GapBackfillRetry>[];

  GapBackfillRetry launch() {
    final GapBackfillRetry r = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: transcriber,
        transcripts: repo,
        isRecording: () => recording,
      ),
      serverStates: states.stream,
      isRecording: () => recording,
      recordingsDirectory: dir.path,
    );
    retries.add(r);
    return r;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  bool markerKept() => repo
      .of(AudioSource.input)
      .any((s) => s.text.startsWith('Transcription interrompue'));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('oats_backfill_retry_');
    repo = InMemoryTranscriptRepository();
    transcriber = _Transcriber();
    states = StreamController<ServerState>.broadcast();
    recording = false;
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

  tearDown(() async {
    for (final GapBackfillRetry r in retries) {
      await r.dispose();
    }
    retries.clear();
    await states.close();
    await dir.delete(recursive: true);
  });

  test('au plus 3 tentatives', () {
    expect(GapBackfillRetry.maxAttempts, 3);
  });

  test('serveur absent : le repère reste, puis il est rattrapé dès que le '
      'serveur est prêt', () async {
    final GapBackfillRetry retry = launch();
    transcriber.available = false;
    await retry.afterSession(sessionId);
    expect(markerKept(), isTrue);
    expect(transcriber.calls, 1);

    transcriber.available = true;
    states.add(ServerState.ready);
    await settle();

    expect(transcriber.calls, 2);
    expect(markerKept(), isFalse);
    expect(repo.of(AudioSource.input).single.text, 'Retrouvé.');
  });

  test('pas de tentative pendant un enregistrement, mais à la disponibilité '
      'suivante hors enregistrement', () async {
    final GapBackfillRetry retry = launch();
    transcriber.available = false;
    await retry.afterSession(sessionId);

    transcriber.available = true;
    recording = true;
    states.add(ServerState.ready);
    await settle();
    expect(transcriber.calls, 1, reason: 'jamais pendant un enregistrement');

    recording = false;
    states.add(ServerState.ready);
    await settle();
    expect(transcriber.calls, 2);
    expect(markerKept(), isFalse);
  });

  test('au lancement suivant, la session en attente est réessayée', () async {
    final GapBackfillRetry first = launch();
    transcriber.available = false;
    await first.afterSession(sessionId);
    await first.dispose();

    transcriber.available = true;
    await launch().retryPending();

    expect(transcriber.calls, 2);
    expect(markerKept(), isFalse);
  });

  test(
    'après 3 tentatives sans serveur, on arrête et le repère reste',
    () async {
      final GapBackfillRetry first = launch();
      transcriber.available = false;
      await first.afterSession(sessionId);
      for (int i = 0; i < 4; i++) {
        states.add(ServerState.ready);
        await settle();
      }
      await first.dispose();
      await launch().retryPending();
      await settle();

      expect(transcriber.calls, 3);
      expect(markerKept(), isTrue);
    },
  );

  test('une session dont le WAV a disparu n est plus réessayée', () async {
    final GapBackfillRetry first = launch();
    transcriber.available = false;
    await first.afterSession(sessionId);
    await File('${dir.path}/${sessionId}_mic.wav').delete();

    transcriber.available = true;
    states.add(ServerState.ready);
    await settle();
    await first.dispose();
    await launch().retryPending();
    await settle();

    expect(transcriber.calls, 1);
    expect(markerKept(), isTrue);
  });

  test('une session rattrapée n est plus réessayée', () async {
    final GapBackfillRetry first = launch();
    await first.afterSession(sessionId);
    states.add(ServerState.ready);
    await settle();
    await first.dispose();
    await launch().retryPending();

    expect(transcriber.calls, 1);
    expect(markerKept(), isFalse);
  });
}

final class _Transcriber implements PcmTranscriber {
  bool available = true;
  int calls = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    if (!available) {
      throw const SocketException('Connection refused');
    }
    return <({int offsetMs, String text})>[(offsetMs: 0, text: 'Retrouvé.')];
  }
}
