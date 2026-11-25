import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
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

/// WAV micro de [ms] ms (parole aux heures de [said]) le temps de [body].
Future<void> _onMicWav(
  String session,
  int ms,
  List<_Said> said,
  Future<void> Function(String dir) body,
) async {
  final Directory dir = await Directory.systemTemp.createTemp('oats_relaunch_');
  try {
    await _wav('${dir.path}/${session}_mic.wav', 'input', ms, said);
    await body(dir.path);
  } finally {
    await dir.delete(recursive: true);
  }
}

InMemorySessionRepository _activeSession(String session) =>
    InMemorySessionRepository()
      ..store[session] = FakeData.createSession(
        id: session,
        status: SessionStatus.active,
      );

TranscriptSegmentEntity _micLine(String session, int k, int atMs) =>
    TranscriptSegmentEntity(
      id: '${session}_input_$k',
      sessionId: session,
      source: AudioSource.input,
      text: _distinct[k % _distinct.length],
      timestampMs: atMs,
      createdAt: DateTime(2026, 11, 25),
    );

/// Repères de perte rattrapables rangés, « heure texte », triés.
List<String> _gapMarkers(InMemoryTranscriptRepository repo) => <String>[
  for (final TranscriptSegmentEntity m in repo.store.values)
    if (m.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
      '${m.timestampMs} ${m.text}',
]..sort();

/// App tuée pendant la réparation : la base meurt à l'écriture qui suit
/// [savesLeft] écritures réussies ; `null` : jamais. Le vrai `save`
/// (core_data, `insertOnConflictUpdate`) écrase un id existant : la map
/// aussi.
final class _KilledDuringRepair extends InMemoryTranscriptRepository {
  int? savesLeft;

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async {
    final int? left = savesLeft;
    if (left != null) {
      if (left == 0) throw StateError('app killed during the launch repair');
      savesLeft = left - 1;
    }
    return super.save(segment);
  }
}

/// Parole 0–5 s (ligne rangée à 0 s), puis deux passages sans ligne,
/// 10–15 s et 30–35 s (écart > 5 s : deux repères, pas un fusionné). Un
/// relancement sans accident donne la référence ; puis l'app meurt après
/// le 1er repère rangé, et l'app relancée répare de nouveau avec une base
/// saine. Rend (référence, repères après les deux lancements).
Future<({List<String> control, List<String> after})> _killedMidRepair({
  required bool sessionStillActive,
}) async {
  const String session = '1700000000000';
  final List<_Said> said = <_Said>[
    for (final (int from, int to) in <(int, int)>[
      (0, 5000),
      (10000, 15000),
      (30000, 35000),
    ])
      (source: 'input', startMs: from, endMs: to, text: 'phrase'),
  ];
  late List<String> control;
  late List<String> after;
  await _onMicWav(session, 40000, said, (String dir) async {
    final TranscriptSegmentEntity first = _micLine(session, 1, 0);
    final InMemoryTranscriptRepository clean = InMemoryTranscriptRepository()
      ..store[first.id] = first;
    await LaunchRepair(
      sessions: _activeSession(session),
      transcripts: clean,
      recordingsDir: dir,
    ).run();
    control = _gapMarkers(clean);

    final InMemorySessionRepository sessions = _activeSession(session);
    final _KilledDuringRepair repo = _KilledDuringRepair()
      ..store[first.id] = first
      ..savesLeft = 1;
    // L'app meurt ici : que `run` propage l'erreur ou non, la base ne
    // reçoit plus rien.
    try {
      await LaunchRepair(
        sessions: sessions,
        transcripts: repo,
        recordingsDir: dir,
      ).run();
    } on StateError catch (_) {}
    if (sessionStillActive) {
      // État forcé : celui que laisse une réparation qui ne ferme la
      // session qu'à la fin (la session reste `active` après l'arrêt).
      sessions.store[session] = FakeData.createSession(
        id: session,
        status: SessionStatus.active,
      );
    }
    repo.savesLeft = null;
    await LaunchRepair(
      sessions: sessions,
      transcripts: repo,
      recordingsDir: dir,
    ).run();
    after = _gapMarkers(repo);
  });
  return (control: control, after: after);
}

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

  // Vraie réunion : parole continue (pauses < 1 s), un seul passage dans le
  // WAV. Lignes rangées à 0 s et 55 s seulement ; celles du milieu ont été
  // refusées par la base puis perdues à l'arrêt brutal.
  // Tolérance (décision du 2026-11-25) : une ligne du direct peut porter
  // jusqu'à la coupe du direct, 30 s ; elle couvre de 2 s avant son heure
  // jusqu'à la ligne suivante,
  // [TranscriptionRemoteDataSourceImpl.maxUtteranceMs] au plus. Donc ~30–53 s
  // doit être sous un repère.
  test('parole continue 60 s, lignes rangées à 0 s et 55 s seulement : '
      'chaque seconde de parole du WAV est près d une ligne rangée (de 2 s '
      'avant à la suivante, coupe du direct au plus) ou sous un '
      'repère', () async {
    const String session = '1700000000000';
    expect(
      <int>[
        for (int c = 0; c < 600; c++)
          if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(
            _chunk(c, 1, true),
          ))
            c,
      ],
      isEmpty,
      reason: 'précondition : chaque chunk est de la parole',
    );
    await _onMicWav(
      session,
      60000,
      <_Said>[(source: 'input', startMs: 0, endMs: 60000, text: 'continu')],
      (String dir) async {
        final InMemoryTranscriptRepository repo =
            InMemoryTranscriptRepository();
        for (final TranscriptSegmentEntity l in <TranscriptSegmentEntity>[
          _micLine(session, 1, 0),
          _micLine(session, 12, 55000),
        ]) {
          repo.store[l.id] = l;
        }
        await LaunchRepair(
          sessions: _activeSession(session),
          transcripts: repo,
          recordingsDir: dir,
        ).run();

        final List<TranscriptSegmentEntity> mic = repo.of(AudioSource.input);
        final List<int> lines = <int>[
          for (final TranscriptSegmentEntity l in mic)
            if (!isTranscriptMarker(l.text)) l.timestampMs,
        ]..sort();
        final List<({int startMs, int endMs})> marked =
            <({int startMs, int endMs})>[
              for (final TranscriptSegmentEntity m in mic)
                if (isTranscriptMarker(m.text) && _range(m.text) != null)
                  _range(m.text)!,
            ];
        final List<int> missing = <int>[];
        for (int s = 0; s < 60000; s += 1000) {
          bool near = false;
          for (int i = 0; i < lines.length; i++) {
            final int end = math.min(
              lines[i] + TranscriptionRemoteDataSourceImpl.maxUtteranceMs,
              i + 1 < lines.length ? lines[i + 1] : 1 << 40,
            );
            if (s >= lines[i] - 2000 && s < end) near = true;
          }
          // Heures des repères à la seconde : ±1 s.
          final bool under = marked.any(
            (({int startMs, int endMs}) r) =>
                r.startMs - 1000 <= s && s < r.endMs + 1000,
          );
          if (!near && !under) missing.add(s ~/ 1000);
        }
        expect(
          missing,
          isEmpty,
          reason:
              'secondes de parole (s) sans ligne proche ni repère : $missing\n'
              'repères : ${mic.where((TranscriptSegmentEntity m) => isTranscriptMarker(m.text)).map((TranscriptSegmentEntity m) => m.text).join(' | ')}',
        );
      },
    );
  });

  test('une seule ligne rangée à 0 s, puis 25 s de parole continue et du '
      'silence : une ligne longue du direct, légitime, pas de repère de '
      'perte', () async {
    const String session = '1700000000000';
    await _onMicWav(
      session,
      35000,
      <_Said>[(source: 'input', startMs: 0, endMs: 25000, text: 'continu')],
      (String dir) async {
        final InMemoryTranscriptRepository repo =
            InMemoryTranscriptRepository();
        final TranscriptSegmentEntity line = _micLine(session, 1, 0);
        repo.store[line.id] = line;
        await LaunchRepair(
          sessions: _activeSession(session),
          transcripts: repo,
          recordingsDir: dir,
        ).run();
        expect(_gapMarkers(repo), isEmpty);
      },
    );
  });

  test('app tuée pendant la réparation du lancement : au lancement suivant, '
      'les mêmes repères qu une réparation sans accident (mêmes plages), '
      'aucun perdu, aucun en double', () async {
    final r = await _killedMidRepair(sessionStillActive: false);
    expect(r.control, hasLength(2), reason: 'scénario : deux passages');
    expect(r.after, r.control);
  });

  test('app tuée pendant la réparation, session encore active au lancement '
      'suivant : le 1er repère garde sa plage, le 2e n écrase rien', () async {
    final r = await _killedMidRepair(sessionStillActive: true);
    expect(r.control, hasLength(2), reason: 'scénario : deux passages');
    expect(r.after, r.control);
  });
}
