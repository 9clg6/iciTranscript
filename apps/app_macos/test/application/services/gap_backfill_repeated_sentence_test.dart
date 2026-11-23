import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Un orateur répète VRAIMENT une phrase presque identique après une pause
// (« Can you hear me now? » … 20 s … « Can you hear me now? » ; « On reprend
// la diapo trois. » deux fois, à 15 s d'écart) et la seconde tombe dans un
// intervalle rattrapé : elle est GARDÉE. Un morceau rattrapé n'est écarté
// comme doublon que si son audio recoupe ou touche (≤ 3 s) l'audio du
// voisin intact qu'il répète, jamais quand c'est une autre prise de parole
// après une pause. Les doublons de fin enregistrés (sondes 9–10,
// gap_backfill_end_duplicates_test) restent écartés.
//
// Banc : vrai WAV ; chaque pas de 100 ms porte son numéro dans ses 4
// premiers échantillons (< 64) ; parlé = ±1000, silence = 0. Le
// transcripteur factice rend les phrases qui commencent dans l'audio
// demandé.
const String _session = '1700000000000';

typedef _Said = ({int startMs, int endMs, String text});

Uint8List _chunk(int c, List<_Said> said) {
  final Uint8List out = Uint8List(3200);
  final ByteData d = ByteData.sublistView(out);
  final bool talk = said.any(
    (_Said s) => c * 100 >= s.startMs && c * 100 < s.endMs,
  );
  for (int i = 0; i < 1600; i++) {
    final int v = switch (i) {
      0 => c % 64,
      1 => (c ~/ 64) % 64,
      2 => c ~/ 4096,
      3 => 1,
      _ => talk ? (i.isEven ? 1000 : -1000) : 0,
    };
    d.setInt16(i * 2, v, Endian.little);
  }
  return out;
}

final class _Heard implements PcmTranscriber {
  _Heard(this.said);

  final List<_Said> said;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final ByteData d = ByteData.sublistView(pcm);
    final int startMs =
        (d.getInt16(0, Endian.little) +
            64 * d.getInt16(2, Endian.little) +
            4096 * d.getInt16(4, Endian.little)) *
        100;
    final int endMs = startMs + pcm.length ~/ 32;
    return <({int offsetMs, String text})>[
      for (final _Said s in said)
        if (s.startMs >= startMs - 500 && s.startMs < endMs)
          (offsetMs: math.max(0, s.startMs - startMs), text: s.text),
    ];
  }
}

/// Rattrape [stored] sur le WAV micro de [said] ; rend la note (micro).
Future<String> _backfill(
  List<_Said> said,
  List<TranscriptSegmentEntity> stored,
  int wavMs,
) async {
  final Directory dir = await Directory.systemTemp.createTemp('oats_repeat_');
  try {
    final WavRecorder recorder = WavRecorder();
    await recorder.open('${dir.path}/${_session}_mic.wav');
    for (int c = 0; c < wavMs ~/ 100; c++) {
      await recorder.append(_chunk(c, said));
    }
    await recorder.close();
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    for (final TranscriptSegmentEntity s in stored) {
      await repo.save(s);
    }
    await GapBackfillService(
      transcriber: _Heard(said),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(_session, recordingsDirectory: dir.path);
    return (repo.of(AudioSource.input)
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs)))
        .map((TranscriptSegmentEntity s) => s.text)
        .join(' | ');
  } finally {
    await dir.delete(recursive: true);
  }
}

TranscriptSegmentEntity _segment(String id, int atMs, String text) =>
    TranscriptSegmentEntity(
      id: id,
      sessionId: _session,
      source: AudioSource.input,
      text: text,
      timestampMs: atMs,
      createdAt: DateTime(2026, 11, 25),
    );

void main() {
  test('« Can you hear me now? » répété 20 s plus tard, au début d une '
      'tranche du rattrapage après la pause : les deux restent', () async {
    // Perte 10–250 s, rien de rangé dedans. La seconde prise commence à
    // 109,2 s, juste après la borne d'une tranche (coupée au silence) : le
    // dernier morceau rendu juste avant est la première prise (89 s).
    const String ask = 'Can you hear me now?';
    final List<_Said> said = <_Said>[
      (startMs: 20000, endMs: 24000, text: 'Hello everyone, let us start.'),
      (startMs: 89000, endMs: 90500, text: ask),
      (startMs: 109200, endMs: 110700, text: ask),
      (startMs: 150000, endMs: 154000, text: 'Yes, we hear you perfectly.'),
    ];
    final String note = await _backfill(said, <TranscriptSegmentEntity>[
      _segment(
        '${_session}_input_1',
        10000,
        LiveTranscriptionService.gapMarkerText(10000, 250000),
      ),
    ], 280000);
    expect(ask.allMatches(note).length, 2, reason: note);
    expect(note, contains('Yes, we hear you perfectly.'));
  });

  test('« On reprend la diapo trois. » répété 15 s plus tard, la perte '
      'commençant pendant la seconde prise : les deux restent', () async {
    // La première prise est rangée en direct (15 s) ; la perte commence
    // à 31,4 s, pendant la seconde prise (30,5–32,1 s), dont le texte est
    // rattrapé en tête de l'intervalle.
    const String again = 'On reprend la diapo trois.';
    final List<_Said> said = <_Said>[
      (startMs: 15000, endMs: 16600, text: again),
      (startMs: 30500, endMs: 32100, text: again),
      (
        startMs: 45000,
        endMs: 49000,
        text: 'Merci, je vois bien le tableau maintenant.',
      ),
    ];
    final String note = await _backfill(said, <TranscriptSegmentEntity>[
      _segment('${_session}_input_1', 15000, again),
      _segment(
        '${_session}_input_2',
        31400,
        LiveTranscriptionService.gapMarkerText(31400, 70000),
      ),
    ], 100000);
    expect(again.allMatches(note).length, 2, reason: note);
    expect(note, contains('je vois bien le tableau'));
  });

  test('garde : la fin d une phrase intacte retranscrite juste après elle '
      '(≤ 3 s) reste écartée', () async {
    // Phrase intacte rangée 9,0–15,6 s ; la perte commence à 16,5 s ; le
    // rattrapage repart à 15,5 s, dans la phrase, et en rend la fin.
    const String intact =
        'Le libraire a rangé la fontaine ronde, puis la gardienne a réparé '
        'la vieille barrière.';
    const String tail = 'puis la gardienne a réparé la vieille barrière.';
    final List<_Said> said = <_Said>[
      (startMs: 9000, endMs: 15600, text: intact),
      (startMs: 15500, endMs: 15600, text: tail),
      (startMs: 30000, endMs: 34000, text: 'The mayor painted the stone wall.'),
    ];
    final String note = await _backfill(said, <TranscriptSegmentEntity>[
      _segment('${_session}_input_1', 9000, intact),
      _segment(
        '${_session}_input_2',
        16500,
        LiveTranscriptionService.gapMarkerText(16500, 50000),
      ),
    ], 60000);
    expect(note, contains('The mayor painted the stone wall.'));
    expect(
      'puis la gardienne a réparé'.allMatches(note).length,
      1,
      reason: note,
    );
  });
}
