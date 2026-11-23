import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../fixtures/probe7_overlap.dart';
import '../../helpers/live_service_fakes.dart';

// Revue PR #25, point 1 : le repère provisoire (mis à jour chaque seconde,
// id `<session>_<source>_pending`) s'écrit sans passer par la fusion, et
// `GapBackfillService.plan` croit ce qui est rangé. Après un arrêt brutal
// pendant une coupure, des repères qui se chevauchent peuvent donc être sur
// le disque. Le rattrapage doit s'en sortir seul.
//
// État rangé de la sonde 7 (Dlag sans rattrapage, son système) : 1:51–2:35
// contient 1:58–2:04 et 2:12–2:14 ; plus un repère provisoire 2:40–3:10
// qui recoupe le repère final 2:45–4:59.
//
// Attendu : un intervalle par union, chaque phrase une seule fois, dans
// l'ordre, aucun repère de l'union laissé, les segments dans l'union
// remplacés une fois (`replacedIds`).
void main() {
  const String sessionId = probe7SessionId;
  final TranscriptSegmentEntity provisional = TranscriptSegmentEntity(
    id: '${sessionId}_output_pending',
    sessionId: sessionId,
    source: AudioSource.output,
    text: LiveTranscriptionService.gapMarkerText(160000, 190000),
    timestampMs: 160000,
    createdAt: DateTime(2026, 11, 24),
  );

  List<TranscriptSegmentEntity> stored() => <TranscriptSegmentEntity>[
    for (final Probe7Segment s in probe7SystemStored)
      TranscriptSegmentEntity(
        id: s.id,
        sessionId: sessionId,
        source: AudioSource.output,
        text: s.text,
        timestampMs: s.timestampMs,
        createdAt: DateTime(2026, 11, 24),
      ),
    provisional,
  ];

  bool isMarker(TranscriptSegmentEntity s) =>
      s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

  test('le plan donne un intervalle par union, et remplace une fois les '
      'segments de l union', () {
    final plan =
        GapBackfillService.plan(
            stored(),
          ).where((p) => p.source == AudioSource.output).toList()
          ..sort((a, b) => a.startMs.compareTo(b.startMs));

    expect(plan, hasLength(3), reason: '0:18–1:15, 1:51–2:35, 2:40–4:59');
    final int margin = GapBackfillService.margin.inMilliseconds;
    expect(plan[1].startMs, lessThanOrEqualTo(111630 - margin));
    expect(plan[2].startMs, lessThanOrEqualTo(160000 - margin));
    final List<String> replaced = <String>[
      for (final p in plan) ...p.replacedIds,
    ];
    expect(replaced.toSet(), hasLength(replaced.length), reason: 'une fois');
    expect(replaced, contains('${sessionId}_output_18'));
  });

  test('après le rattrapage : chaque phrase une fois, dans l ordre, plus '
      'aucun repère de ces unions', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'oats_overlapping_markers_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final WavRecorder recorder = WavRecorder();
    await recorder.open('${dir.path}/${sessionId}_system.wav');
    for (int c = 0; c < 3200; c++) {
      final Uint8List chunk = Uint8List(3200);
      final ByteData d = ByteData.sublistView(chunk);
      for (int o = 0; o < 3200; o += 2) {
        d.setInt16(o, c * 4 + 2, Endian.little);
      }
      await recorder.append(chunk);
    }
    await recorder.close();
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    for (final TranscriptSegmentEntity s in stored()) {
      await repo.save(s);
    }

    await GapBackfillService(
      transcriber: _Recorded(),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(sessionId, recordingsDirectory: dir.path);

    final List<TranscriptSegmentEntity> lines = repo.of(AudioSource.output)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    expect(
      lines.where(
        (TranscriptSegmentEntity s) => isMarker(s) && s.timestampMs >= 100000,
      ),
      isEmpty,
      reason: 'repères des deux unions retirés',
    );
    int last = -1;
    for (final ({int atMs, String text}) p in probe7SystemRecovered.where(
      (({int atMs, String text}) p) => p.atMs >= 100000,
    )) {
      final String clause = p.text.split(',').first;
      final List<int> at = <int>[
        for (int i = 0; i < lines.length; i++)
          if (lines[i].text.contains(clause)) i,
      ];
      expect(at, hasLength(1), reason: '« $clause » une seule fois');
      expect(at.single, greaterThan(last), reason: '« $clause » dans l ordre');
      last = at.single;
    }
  });
}

/// Texte du rattrapage enregistré, choisi par l'heure du PCM demandé (chaque
/// échantillon d'un pas de 100 ms vaut numéro × 4 + piste).
final class _Recorded implements PcmTranscriber {
  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final int v = ByteData.sublistView(pcm).getInt16(0, Endian.little);
    final int startMs = (v ~/ 4) * 100;
    final int endMs = startMs + pcm.length ~/ 32;
    return <({int offsetMs, String text})>[
      for (final ({int atMs, String text}) p in probe7SystemRecovered)
        if (p.atMs >= startMs - 1500 && p.atMs < endMs)
          (offsetMs: p.atMs - startMs, text: p.text),
    ];
  }
}
