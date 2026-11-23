import 'dart:async';
import 'dart:io';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/voiced_pcm.dart';

/// Un seul serveur de transcription, séquentiel (un 3e flux fait exploser
/// les délais, mesuré) : un arbitre, priorité enregistrement > dictée >
/// rattrapage des pertes.
///
/// API supposée (lib/application/services/transcription_server_arbiter.dart) :
/// - `TranscriptionServerArbiter({required bool Function() isRecording})` ;
/// - `void dictationStarted()`, `void dictationEnded()` (appelés par le
///   DictationController, de l'appui à la fin de la dictée) ;
/// - `bool get backfillMustYield` : enregistrement ou dictée en cours ;
/// - `Stream<void> get backfillMayResume` : émis quand une dictée finit
///   hors enregistrement (le serveur redevient libre pour le rattrapage).
///
/// `GapBackfillRetry(..., Stream<void>? resumeSignals)` : comme un serveur
/// redevenu prêt, chaque signal relance les sessions en attente.
/// En production, `gapBackfillRetryProvider` doit lire `backfillMustYield`
/// (au lieu de « enregistrement » seul) et brancher `backfillMayResume`.
void main() {
  group('arbitre', () {
    bool recording = false;
    late TranscriptionServerArbiter arbiter;

    setUp(() {
      recording = false;
      arbiter = TranscriptionServerArbiter(isRecording: () => recording);
    });

    test('serveur libre : le rattrapage peut tourner', () {
      expect(arbiter.backfillMustYield, isFalse);
    });

    test('un enregistrement ou une dictée : le rattrapage cède', () {
      recording = true;
      expect(arbiter.backfillMustYield, isTrue);
      recording = false;
      arbiter.dictationStarted();
      expect(arbiter.backfillMustYield, isTrue);
    });

    test(
      'fin de dictée hors enregistrement : le rattrapage peut reprendre',
      () async {
        int resumes = 0;
        arbiter.backfillMayResume.listen((_) => resumes++);
        arbiter.dictationStarted();

        arbiter.dictationEnded();
        await pumpEventQueue();

        expect(arbiter.backfillMustYield, isFalse);
        expect(resumes, 1);
      },
    );

    test('fin de dictée pendant un enregistrement : le rattrapage attend '
        'encore', () async {
      int resumes = 0;
      arbiter.backfillMayResume.listen((_) => resumes++);
      recording = true;
      arbiter.dictationStarted();

      arbiter.dictationEnded();
      await pumpEventQueue();

      expect(arbiter.backfillMustYield, isTrue);
      expect(resumes, 0);
    });
  });

  group('rattrapage en cours, une dictée commence (temps réel)', () {
    const String sessionId = '1700000000000';
    late Directory dir;

    setUp(() async {
      dir = Directory(LiveTranscriptionService.recordingsDir);
      expect(dir.path, startsWith(Directory.systemTemp.path));
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      // 66 s de micro, chaque chunk de 100 ms porte son numéro.
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_mic.wav');
      for (int id = 0; id < 660; id++) {
        await recorder.append(voicedChunk(<int>[id & 0x7FFF, id >> 15]));
      }
      await recorder.close();
    });

    test('aucun morceau ne part après le début de la dictée ; à sa fin, le '
        'rattrapage reprend et remplace le repère', () async {
      final TranscriptionServerArbiter arbiter = TranscriptionServerArbiter(
        isRecording: () => false,
      );
      final FakeVoxServer vox = FakeVoxServer();
      final List<FakeVoxSocket> sockets = <FakeVoxSocket>[];
      final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
      // Perte de 1 s à 64 s : marge comprise, trois morceaux de 30 s au plus.
      await repo.save(
        TranscriptSegmentEntity(
          id: 'm',
          sessionId: sessionId,
          source: AudioSource.input,
          text: LiveTranscriptionService.gapMarkerText(1000, 64000),
          timestampMs: 1000,
          createdAt: DateTime(2026, 11, 22, 10),
        ),
      );
      final GapBackfillRetry retry = GapBackfillRetry(
        backfill: GapBackfillService(
          transcriber: WebSocketPcmTranscriber(
            url: 'ws://test',
            createClient: () {
              final FakeVoxSocket socket = FakeVoxSocket(vox);
              sockets.add(socket);
              return socket;
            },
            shouldYield: () => arbiter.backfillMustYield,
          ),
          transcripts: repo,
          isRecording: () => arbiter.backfillMustYield,
        ),
        serverStates: const Stream<ServerState>.empty(),
        isRecording: () => arbiter.backfillMustYield,
        recordingsDirectory: dir.path,
        resumeSignals: arbiter.backfillMayResume,
      );
      addTearDown(retry.dispose);

      unawaited(retry.afterSession(sessionId));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(sockets, isNotEmpty, reason: 'le premier morceau est parti');
      arbiter.dictationStarted();
      final int sentAtDictation = sockets.fold<int>(
        0,
        (int n, FakeVoxSocket s) => n + s.receivedIds.length,
      );
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(
        sockets.fold<int>(
          0,
          (int n, FakeVoxSocket s) => n + s.receivedIds.length,
        ),
        sentAtDictation,
        reason: 'rien envoyé pendant la dictée',
      );
      expect(repo.store.containsKey('m'), isTrue, reason: 'repère gardé');

      arbiter.dictationEnded();
      for (int i = 0; i < 100 && repo.store.containsKey('m'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(
        repo.store.containsKey('m'),
        isFalse,
        reason: 'repris et remplacé',
      );
      expect(repo.of(AudioSource.input), isNotEmpty);
    });
  });
}
