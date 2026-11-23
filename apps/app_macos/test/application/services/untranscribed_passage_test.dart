import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/voiced_pcm.dart';

// Tour 7, point 4 — CHANGEMENT de décision. Sonde 5 : retranscrire ne répare
// pas une phrase que le modèle rate de façon déterministe (3× du français
// abîmé, 1× de l'anglais sans rapport, 1× rien). Une phrase finale en
// écriture non latine ou en langue non attendue, AVEC de la parole, devient
// un repère PERMANENT « passage non transcrit » : jamais envoyé au
// rattrapage, jamais remplacé par une sortie du modèle, gardé au
// relancement. Sans parole, le texte est écarté comme avant. Distinct du
// repère de coupure « Transcription interrompue… ».
//
// API supposée : `LiveTranscriptionService.untranscribedMarkerText(int
// startMs, int endMs)` (texte rangé) et `LiveTranscriptionService
// .isUntranscribedMarker(String text)`. L'affichage localisé est spécifié
// dans session_detail_untranscribed_test.dart.
void main() {
  group('service en direct', () {
    UtteranceWindow window(LiveServiceHarness h, int s, int e, bool speech) =>
        UtteranceWindow(startMs: h.t0 + s, endMs: h.t0 + e, hadSpeech: speech);

    for (final String wrong in <String>[
      'नमस्ते आप सब कैसे हैं आज',
      'El equipo ha terminado el presupuesto para el próximo trimestre.',
    ]) {
      test('« $wrong » avec parole : un repère permanent sur l intervalle de '
          'la phrase, pas un repère de coupure', () {
        fakeAsync((FakeAsync async) {
          final LiveServiceHarness h = LiveServiceHarness(async)..start();
          h.fakeRemote.emitDone(
            AudioSource.output,
            wrong,
            window: window(h, 62000, 68000, true),
          );
          async.elapse(const Duration(seconds: 1));

          final TranscriptSegmentEntity marker = h.segments
              .of(AudioSource.output)
              .single;
          expect(
            LiveTranscriptionService.isUntranscribedMarker(marker.text),
            isTrue,
          );
          expect(
            marker.text,
            isNot(startsWith(LiveTranscriptionService.gapMarkerPrefix)),
          );
          expect(marker.timestampMs, 62000);
          expect(
            marker.text,
            LiveTranscriptionService.untranscribedMarkerText(62000, 68000),
          );
        });
      });
    }

    test('sans parole, le texte non latin est écarté comme avant', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        h.fakeRemote.emitDone(
          AudioSource.output,
          'नमस्ते आप सब कैसे हैं आज',
          window: window(h, 62000, 68000, false),
        );
        async.elapse(const Duration(seconds: 1));

        expect(h.segments.of(AudioSource.output), isEmpty);
      });
    });
  });

  group('jamais rattrapé', () {
    const String sessionId = '1700000000000';
    late Directory dir;
    late InMemoryTranscriptRepository repo;
    late _Counting transcriber;
    late TranscriptSegmentEntity passage;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_untranscribed_');
      repo = InMemoryTranscriptRepository();
      transcriber = _Counting();
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_system.wav');
      await recorder.append(voicedPcm(90 * 32000));
      await recorder.close();
      passage = TranscriptSegmentEntity(
        id: 'p',
        sessionId: sessionId,
        source: AudioSource.output,
        text: LiveTranscriptionService.untranscribedMarkerText(62000, 68000),
        timestampMs: 62000,
        createdAt: DateTime(2026, 11, 23),
      );
      await repo.save(passage);
    });

    tearDown(() => dir.delete(recursive: true));

    GapBackfillService backfill() => GapBackfillService(
      transcriber: transcriber,
      transcripts: repo,
      isRecording: () => false,
    );

    test('le plan ne le retient pas', () {
      expect(
        GapBackfillService.plan(<TranscriptSegmentEntity>[passage]),
        isEmpty,
      );
    });

    test(
      'le rattrapage ne l envoie pas au modèle et ne le remplace pas',
      () async {
        await backfill().backfill(sessionId, recordingsDirectory: dir.path);

        expect(transcriber.calls, 0);
        expect(repo.store.values.single, passage);
      },
    );

    test('ni la fin de session, ni « serveur prêt », ni le relancement ne le '
        'réessaient ; il reste', () async {
      final StreamController<ServerState> states =
          StreamController<ServerState>.broadcast();
      GapBackfillRetry launch() => GapBackfillRetry(
        backfill: backfill(),
        serverStates: states.stream,
        isRecording: () => false,
        recordingsDirectory: dir.path,
      );
      final GapBackfillRetry first = launch();
      await first.afterSession(sessionId);
      states.add(ServerState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await first.dispose();
      final GapBackfillRetry second = launch();
      await second.retryPending();
      await second.dispose();
      await states.close();

      expect(transcriber.calls, 0);
      expect(repo.store.values.single, passage);
    });
  });
}

final class _Counting implements PcmTranscriber {
  int calls = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    return <({int offsetMs, String text})>[
      (offsetMs: 0, text: 'Le libraire a mesuré la cabane.'),
    ];
  }
}
