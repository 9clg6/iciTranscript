import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';

// Tour 7, exception à la règle par le temps (ajoutée par l'implémentation
// pour garder gap_backfill_overlap_test vert) : un segment qui commence à
// la FIN de la perte ou après, et dont le début se retrouve tel quel dans
// le texte rattrapé, est gardé (le doublon est retiré du texte rattrapé) ;
// tout ce qui commence avant la fin est remplacé.
//
// Constat sur les séquences enregistrées (sonde 5) : aucun segment remplacé
// ne commence à la fin de la perte ou après ; les phrases abîmées du bord
// (« Grafie et le lavoir… » à 73,0 s pour une fin à 74,0 s, « In the green
// bench… » à 74,3 s pour 79,0 s) commencent AVANT la fin. L'exception n'y
// joue donc jamais. Les cas ci-dessous la font jouer sur les textes
// enregistrés (même audio : les segments en direct de D, le texte
// rattrapé de la réunion A des réunions à la suite), en déplaçant la fin de
// la perte.
const int _tolerance = 2000;

String _norm(String t) => t
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  test('séquences enregistrées : aucun segment de la fenêtre ne commence à '
      'la fin de la perte ou après (l exception n y joue pas)', () {
    for (final ProbeScenario sc in <ProbeScenario>[
      probeD,
      probeRelaunch,
      probeBackToBack,
    ]) {
      for (final ProbeGap g in sc.gaps) {
        final Iterable<ProbeSegment> atOrAfterEnd = sc.segments.where(
          (ProbeSegment s) =>
              s.source == g.source &&
              s.timestampMs >= g.markerEndMs &&
              s.timestampMs <= g.markerEndMs + _tolerance,
        );
        expect(atOrAfterEnd, isEmpty, reason: '${sc.name} ${g.markerId}');
      }
    }
  });

  group('l exception jouée sur les textes enregistrés (son système de D)', () {
    const String sessionId = '1795385073459';
    final ProbeGap dOutput = probeD.gaps.firstWhere(
      (ProbeGap g) => g.source == 'output',
    );
    final ProbeGap aOutput = probeBackToBack.gaps.firstWhere(
      (ProbeGap g) => g.source == 'output',
    );
    late Directory dir;
    late InMemoryTranscriptRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_edge_exception_');
      repo = InMemoryTranscriptRepository();
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_system.wav');
      await recorder.append(Uint8List(160 * 32000));
      await recorder.close();
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> seed(int markerEndMs) async {
      for (final ProbeSegment s in probeD.segments.where(
        (ProbeSegment s) => s.source == 'output',
      )) {
        await repo.save(
          TranscriptSegmentEntity(
            id: s.id,
            sessionId: sessionId,
            source: AudioSource.output,
            text: s.text,
            timestampMs: s.timestampMs,
            createdAt: DateTime(2026, 11, 23),
          ),
        );
      }
      await repo.save(
        TranscriptSegmentEntity(
          id: dOutput.markerId,
          sessionId: sessionId,
          source: AudioSource.output,
          text: LiveTranscriptionService.gapMarkerText(
            dOutput.markerStartMs,
            markerEndMs,
          ),
          timestampMs: dOutput.markerStartMs,
          createdAt: DateTime(2026, 11, 23),
        ),
      );
    }

    /// Texte rattrapé enregistré (même audio), en heures absolues, jusqu'à
    /// [untilMs] ; rendu relatif au début de l'intervalle demandé.
    Future<void> backfill({required int untilMs}) async {
      final GapBackfillService service = GapBackfillService(
        transcriber: _Absolute(<({int atMs, String text})>[
          for (final ({int offsetMs, String text}) p in aOutput.recovered)
            if (aOutput.planStartMs + p.offsetMs < untilMs)
              (atMs: aOutput.planStartMs + p.offsetMs, text: p.text),
        ], () => _lastPlanStart),
        transcripts: repo,
        isRecording: () => false,
      );
      final List<TranscriptSegmentEntity> segments = await repo.getBySessionId(
        sessionId,
      );
      _lastPlanStart = GapBackfillService.plan(segments).single.startMs;
      await service.backfill(sessionId, recordingsDirectory: dir.path);
    }

    List<String> texts() =>
        (repo.of(AudioSource.output)
              ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs)))
            .map((TranscriptSegmentEntity s) => _norm(s.text))
            .toList();

    int count(String clause) => texts()
        .map((String t) => RegExp(RegExp.escape(_norm(clause))).allMatches(t))
        .fold<int>(0, (int n, Iterable<Match> m) => n + m.length);

    test('phrase intacte qui commence à la fin de la perte : gardée telle '
        'quelle, une seule fois', () async {
      // Perte finie à 83,0 s : « Le libraire a décoré le kiosque… »
      // (83,7 s) commence après la fin, intacte, et le texte rattrapé la
      // contient mot pour mot.
      await seed(83000);
      final TranscriptSegmentEntity live =
          repo.store['1795385073459_output_22']!;

      await backfill(untilMs: 92817);

      expect(repo.store['1795385073459_output_22'], live);
      expect(count('Le libraire a décoré le kiosque à journaux'), 1);
      expect(repo.store.containsKey('1795385073459_output_13'), isFalse);
      expect(repo.store.containsKey('1795385073459_output_21'), isFalse);
      expect(count('The mayor measured the round fountain'), 1);
    });

    test('phrase abîmée qui commence à la fin de la perte : remplacée, pas '
        'gardée', () async {
      // Perte finie à 74,0 s : « In the green bench… » (74,3 s) commence
      // après la fin ; son début n'est pas dans le texte rattrapé.
      await seed(74000);

      await backfill(untilMs: 83717);

      expect(repo.store.containsKey('1795385073459_output_21'), isFalse);
      expect(count('in the green bench despite'), 0, reason: 'texte abîmé');
      expect(count('The baker photographed the green bench'), 1);
      expect(count('Le libraire a décoré le kiosque à journaux'), 1);
    });
  });
}

int _lastPlanStart = 0;

final class _Absolute implements PcmTranscriber {
  _Absolute(this.pieces, this.planStart);

  final List<({int atMs, String text})> pieces;
  final int Function() planStart;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final int start = planStart();
    final int end = start + pcm.length ~/ 32;
    return <({int offsetMs, String text})>[
      for (final ({int atMs, String text}) p in pieces)
        if (p.atMs >= start - 1000 && p.atMs < end)
          (offsetMs: p.atMs - start, text: p.text),
    ];
  }
}
