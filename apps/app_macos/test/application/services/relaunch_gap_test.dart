import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/launch_repair.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../fixtures/diskfull_run2.dart';
import '../../helpers/fake_data.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart' show coverage;

// Sonde disque réel sur main 10380a4 (scratchpad/probe/diskfull, run 2) :
// arrêt brutal à 300 s pendant que le disque est plein, puis relancement.
// Les phrases micro 12–14 (audio 149–179 s) ne sont ni rangées ni sous un
// repère : transcrites, mais seulement en mémoire (base qui refusait) ;
// leur AUDIO est dans le WAV (fin du WAV micro : 3:49). `LaunchRepair`
// ouvre « Rien n'a pu être enregistré après… » à max(fin du dernier
// segment rangé, fin du WAV) = 3:49, après elles : le rattrapage n'y
// regarde jamais. En plus, la base a rangé une ligne PLUS TARDIVE
// (`_input_22`, 186,99 s) que les lignes refusées : les reprises se
// rangent dans le désordre.
//
// Conception voulue, par source, au relancement :
// (a) un repère de perte ordinaire, rattrapable, sur l'audio du WAV qui
//     n'a pas de ligne rangée (l'audio existe : le rattrapage le
//     transcrit et ne retire le repère que s'il le rend) ; pas de (a) sous
//     ~1 s ;
// (b) le repère ouvert « Rien n'a pu être enregistré après » depuis la fin
//     du WAV seulement.
//
// Lignes refusées AVANT une ligne rangée plus tard (désordre) : la base ne
// dit pas quelles lignes ont été refusées. Pour l'invariant, (a) doit
// couvrir chaque passage du WAV sans ligne rangée qui peut contenir une
// phrase — pas seulement l'audio après la DERNIÈRE ligne rangée — sinon
// les phrases refusées avant une ligne rangée plus tard restent hors de la
// note et hors repère.
//
// Rejeu : la base telle que le relancement l'a trouvée (relaunch.jsonl,
// « before_repair »), session active ; WAV micro de 229,5 s et système de
// 196,7 s, parole aux heures de capture des lignes du direct ; vraie
// `LaunchRepair`, puis vrai rattrapage avec un transcripteur sain (rend
// les phrases qui commencent dans l'audio demandé, rien pour le silence).
// Invariant : chaque phrase dite est dans la note (60 % de ses mots dans
// l'ordre, près de son heure) OU sous un repère.

/// Chunk de 100 ms. Chaque bloc de 16 échantillons (1 ms) commence par
/// son heure (numéro du chunk en base 64, milliseconde dans le chunk,
/// piste : valeurs < 100, sous la porte de parole), puis parole (±1000) ou
/// silence (0) : le transcripteur factice relit l'heure de départ de
/// n'importe quel morceau lu à la milliseconde (le rattrapage lit à des
/// heures qui ne tombent pas sur un chunk).
Uint8List _chunk(int c, int tag, bool talk) {
  final Uint8List out = Uint8List(3200);
  final ByteData d = ByteData.sublistView(out);
  for (int i = 0; i < 1600; i++) {
    final int k = i % 16;
    final int v = switch (k) {
      0 => c % 64,
      1 => c ~/ 64,
      2 => i ~/ 16,
      3 => tag,
      _ => talk ? (i.isEven ? 1000 : -1000) : 0,
    };
    d.setInt16(i * 2, v, Endian.little);
  }
  return out;
}

typedef _Said = ({String source, int startMs, int endMs, String text});

Future<void> _wav(String path, String source, int ms, List<_Said> said) async {
  final WavRecorder r = WavRecorder();
  await r.open(path);
  final int tag = source == 'input' ? 1 : 2;
  for (int c = 0; c < ms ~/ 100; c++) {
    final bool talk = said.any(
      (_Said s) =>
          s.source == source && c * 100 >= s.startMs && c * 100 < s.endMs,
    );
    await r.append(_chunk(c, tag, talk));
  }
  await r.close();
}

final class _Healthy implements PcmTranscriber {
  _Healthy(this.said);

  final List<_Said> said;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final ByteData d = ByteData.sublistView(pcm);
    final int startMs =
        (d.getInt16(0, Endian.little) + 64 * d.getInt16(2, Endian.little)) *
            100 +
        d.getInt16(4, Endian.little);
    final String source = d.getInt16(6, Endian.little) == 1
        ? 'input'
        : 'output';
    final int endMs = startMs + pcm.length ~/ 32;
    return <({int offsetMs, String text})>[
      for (final _Said s in said)
        if (s.source == source &&
            s.startMs >= startMs - 500 &&
            s.startMs < endMs)
          (offsetMs: math.max(0, s.startMs - startMs), text: s.text),
    ];
  }
}

({int startMs, int endMs})? _range(String text) {
  final List<int> t = <int>[
    for (final RegExpMatch m in RegExp(
      r'(\d+):(\d{2}):(\d{2})',
    ).allMatches(text))
      ((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 60 +
              int.parse(m.group(3)!)) *
          1000,
  ];
  if (LiveTranscriptionService.isNotRecordedAfterMarker(text) && t.isNotEmpty) {
    return (startMs: t.first, endMs: 1 << 40);
  }
  return t.length < 2 ? null : (startMs: t[0], endMs: t[1]);
}

/// Relancement : vraie réparation, puis vrai rattrapage ; rend les phrases
/// ni dans la note ni sous un repère, et la note.
Future<({List<String> neither, List<TranscriptSegmentEntity> lines})>
_relaunch({
  required String session,
  required List<TranscriptSegmentEntity> stored,
  required Map<String, int> wavMs,
  required List<_Said> said,
}) async {
  final Directory dir = await Directory.systemTemp.createTemp('oats_relaunch_');
  try {
    for (final MapEntry<String, int> w in wavMs.entries) {
      await _wav(
        '${dir.path}/${session}_${w.key == 'input' ? 'mic' : 'system'}.wav',
        w.key,
        w.value,
        said,
      );
    }
    final InMemorySessionRepository sessions = InMemorySessionRepository();
    sessions.store[session] = FakeData.createSession(
      id: session,
      status: SessionStatus.active,
    );
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    for (final TranscriptSegmentEntity s in stored) {
      await repo.save(s);
    }
    await LaunchRepair(
      sessions: sessions,
      transcripts: repo,
      recordingsDir: dir.path,
    ).run();
    await GapBackfillService(
      transcriber: _Healthy(said),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(session, recordingsDirectory: dir.path);

    final List<TranscriptSegmentEntity> lines = repo.store.values.toList();
    final List<String> neither = <String>[];
    for (final _Said s in said) {
      final AudioSource src = sourceOf(s.source);
      final bool inNote = lines.any(
        (TranscriptSegmentEntity l) =>
            l.source == src &&
            !isTranscriptMarker(l.text) &&
            l.timestampMs >= s.startMs - 10000 &&
            l.timestampMs <= s.endMs + 2000 &&
            coverage(s.text, l.text) >= 0.6,
      );
      final bool covered = lines.any((TranscriptSegmentEntity m) {
        final ({int startMs, int endMs})? r =
            m.source == src && isTranscriptMarker(m.text)
            ? _range(m.text)
            : null;
        return r != null &&
            r.startMs <= s.startMs + 1000 &&
            r.endMs + 1000 >= s.endMs;
      });
      if (!inNote && !covered) {
        neither.add('${s.source} ${s.startMs} ms « ${s.text} »');
      }
    }
    return (neither: neither, lines: lines);
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Phrases sans suite de mots communs (le critère « 60 % des mots » ne
/// les confond pas).
const List<String> _distinct = <String>[
  'Bonjour à tous, nous ouvrons la réunion budgétaire du trimestre.',
  'Marie présentera ensuite les chiffres des ventes régionales.',
  'Quelqu un peut-il partager son écran avec le tableau complet ?',
  'Le serveur de test tombe chaque lundi vers midi depuis août.',
  'Il faudra renégocier ce contrat avant la fin novembre.',
  'Notre équipe support manque de deux personnes cet hiver.',
  'Merci beaucoup pour cette synthèse très claire et précise.',
];

AudioSource sourceOf(String s) =>
    s == 'input' ? AudioSource.input : AudioSource.output;

void main() {
  test(
    'rejeu du run 2 : après la réparation et le rattrapage, chaque phrase '
    'dite est dans la note ou sous un repère (micro 12–14 compris)',
    () async {
      final List<_Said> said = <_Said>[
        for (final s in diskFullSpoken)
          if (s.endMs <= diskFullKillMs - 5000)
            (
              source: s.source,
              startMs: s.startMs,
              endMs: s.endMs,
              text: s.text,
            ),
      ];
      final r = await _relaunch(
        session: diskFullSessionId,
        stored: <TranscriptSegmentEntity>[
          for (final s in diskFullStored)
            TranscriptSegmentEntity(
              id: s.id,
              sessionId: diskFullSessionId,
              source: sourceOf(s.source),
              text: s.text,
              timestampMs: s.timestampMs,
              createdAt: DateTime(2026, 11, 25),
            ),
        ],
        wavMs: <String, int>{
          'input': diskFullMicWavMs,
          'output': diskFullSystemWavMs,
        },
        said: said,
      );
      expect(r.neither, isEmpty, reason: r.neither.join('\n'));
      // (b) reste ouvert depuis la fin du WAV, jamais avant.
      final TranscriptSegmentEntity open = r.lines.singleWhere(
        (TranscriptSegmentEntity m) =>
            m.source == AudioSource.input &&
            LiveTranscriptionService.isNotRecordedAfterMarker(m.text),
      );
      expect(open.timestampMs, greaterThanOrEqualTo(diskFullMicWavMs - 1000));
    },
  );

  test('lignes refusées AVANT une ligne rangée plus tard : rattrapées depuis '
      'le WAV, la ligne rangée n est pas en double', () async {
    const String session = '1700000000000';
    // Phrases toutes les 10 s, 7,5 s ; la base a rangé 0 s et 60 s,
    // refusé 10–50 s (gardées en mémoire, perdues à l'arrêt brutal).
    final List<_Said> said = <_Said>[
      for (int k = 0; k <= 6; k++)
        (
          source: 'input',
          startMs: k * 10000,
          endMs: k * 10000 + 7500,
          text: _distinct[k],
        ),
    ];
    final r = await _relaunch(
      session: session,
      stored: <TranscriptSegmentEntity>[
        for (final int k in <int>[0, 6])
          TranscriptSegmentEntity(
            id: '${session}_input_${k + 1}',
            sessionId: session,
            source: AudioSource.input,
            text: said[k].text,
            timestampMs: said[k].startMs,
            createdAt: DateTime(2026, 11, 25),
          ),
      ],
      wavMs: <String, int>{'input': 70000},
      said: said,
    );
    expect(r.neither, isEmpty, reason: r.neither.join('\n'));
    final String note = r.lines
        .where((TranscriptSegmentEntity l) => !isTranscriptMarker(l.text))
        .map((TranscriptSegmentEntity l) => l.text)
        .join(' | ');
    for (final _Said s in said) {
      expect(
        s.text.allMatches(note).length,
        lessThanOrEqualTo(1),
        reason: 'en double : $note',
      );
    }
  });

  test('rien ne manque entre la dernière ligne et la fin du WAV (< 1 s) : '
      'pas de repère rattrapable en plus', () async {
    const String session = '1700000000000';
    final List<_Said> said = <_Said>[
      (source: 'input', startMs: 0, endMs: 7500, text: 'Bonjour à tous.'),
      (source: 'input', startMs: 10000, endMs: 17500, text: 'On commence.'),
    ];
    final r = await _relaunch(
      session: session,
      stored: <TranscriptSegmentEntity>[
        for (int k = 0; k < 2; k++)
          TranscriptSegmentEntity(
            id: '${session}_input_${k + 1}',
            sessionId: session,
            source: AudioSource.input,
            text: said[k].text,
            timestampMs: said[k].startMs,
            createdAt: DateTime(2026, 11, 25),
          ),
      ],
      wavMs: <String, int>{'input': 18000},
      said: said,
    );
    expect(
      r.lines.where(
        (TranscriptSegmentEntity m) =>
            m.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      ),
      isEmpty,
    );
  });
}
