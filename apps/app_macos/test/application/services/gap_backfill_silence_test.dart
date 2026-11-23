import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
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
import '../../helpers/recorded_backfill.dart' show markerRange;

// Revue de la PR #28 (bloquant) : toutes les sondes et tous les rejeux
// avaient un audio SANS pause entre les phrases ; en réunion le micro se
// tait le plus souvent, une perte couvre souvent des minutes de silence, et
// les tranches de 100 s du rattrapage n'ont jamais rencontré de tranche
// vide.
//
// Banc : vrai WAV, phrases (carré ±3000, au-dessus de la porte de parole),
// silence numérique (0) ou bruit de salle (±75, sous la porte). Chaque pas
// de 100 ms porte son numéro dans ses 4 premiers échantillons, en valeurs
// < 64 (sans effet sur la porte). Le transcripteur factice rend les phrases
// entendues dans l'audio demandé (début ou fin coupés au prorata), rien
// pour le silence — ou, second cas, une hallucination courte (« Merci. »,
// « Thank you. ») pour chaque bloc de 12 s tout silencieux, comme le vrai.
//
// La porte de parole de `gap_backfill.service.dart:639` sert à COUPER une
// tranche au silence (`_cutAtSilence`), pas à filtrer un morceau avant de
// le ranger : ces specs le disent par le comportement.
//
// Attendu :
// 1. trou de 6 min, parole les 30 premières et 30 dernières secondes,
//    silence entre : la parole d'après le silence revient une fois ; plus
//    de repère sur le silence une fois le rattrapage fini ; aucun texte
//    halluciné rangé pour une tranche silencieuse ; les tentatives
//    s'arrêtent (une tranche vide est un progrès, pas une boucle : appels
//    bornés) ; le fichier d'attente est vidé ;
// 2. une phrase coupée par une borne de tranche après un long silence :
//    aucun mot perdu, aucun doublon ;
// 3. un repère de coupure en direct pendant un long silence : rien de dit
//    n'a été perdu ; après l'arrêt et le rattrapage, aucun « Transcription
//    interrompue » ne reste sur ce silence.
const String _session = '1700000000000';
const List<String> _hallucinations = <String>['Merci.', 'Thank you.'];

typedef _Sentence = ({int startMs, int endMs, String text});

String _text(int k) =>
    'Phrase lue $k, le facteur répare la barrière numéro $k ce matin.';

/// Phrases sans suite de mots communs : la coupe d'un début qui répète la
/// fin du voisin ne peut pas les confondre.
const List<String> _distinct = <String>[
  'Bonjour à tous, nous ouvrons la réunion budgétaire du trimestre.',
  'Ensuite Marie présentera les chiffres des ventes régionales.',
  'Quelqu un peut-il partager son écran avec le tableau complet ?',
  'Merci beaucoup pour cette synthèse très claire et précise.',
];

/// Timeline d'une piste : phrases, et bruit de salle (sinon silence 0).
final class _Track {
  _Track(this.sentences, {this.noise = const <(int, int)>[]});

  final List<_Sentence> sentences;
  final List<(int, int)> noise;

  bool speech(int ms) =>
      sentences.any((_Sentence s) => ms >= s.startMs && ms < s.endMs);

  bool noisy(int ms) => noise.any(((int, int) n) => ms >= n.$1 && ms < n.$2);

  Uint8List chunkAt(int c, int tag) {
    final Uint8List out = Uint8List(3200);
    final ByteData d = ByteData.sublistView(out);
    final bool talk = speech(c * 100);
    final bool room = noisy(c * 100);
    for (int i = 0; i < 1600; i++) {
      int v;
      if (i == 0) {
        v = c % 64;
      } else if (i == 1) {
        v = (c ~/ 64) % 64;
      } else if (i == 2) {
        v = c ~/ 4096;
      } else if (i == 3) {
        v = tag;
      } else if (talk) {
        v = i.isEven ? 3000 : -3000;
      } else if (room) {
        v = ((c * 7 + i * 13) % 151) - 75;
      } else {
        v = 0;
      }
      d.setInt16(i * 2, v, Endian.little);
    }
    return out;
  }
}

Future<void> _writeWav(String path, _Track track, int ms, int tag) async {
  final WavRecorder recorder = WavRecorder();
  await recorder.open(path);
  for (int c = 0; c < ms ~/ 100; c++) {
    await recorder.append(track.chunkAt(c, tag));
  }
  await recorder.close();
}

final class _Transcriber implements PcmTranscriber {
  _Transcriber(this.track, {this.hallucinate = false});

  final _Track track;
  final bool hallucinate;
  int calls = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    final ByteData d = ByteData.sublistView(pcm);
    final int c =
        d.getInt16(0, Endian.little) +
        64 * d.getInt16(2, Endian.little) +
        4096 * d.getInt16(4, Endian.little);
    final int startMs = c * 100;
    final int endMs = startMs + pcm.length ~/ 32;
    final List<({int offsetMs, String text})> out =
        <({int offsetMs, String text})>[];
    for (final _Sentence s in track.sentences) {
      if (s.endMs <= startMs || s.startMs >= endMs) continue;
      final List<String> words = s.text.split(' ');
      final int from = s.startMs >= startMs
          ? 0
          : (words.length * (startMs - s.startMs) / (s.endMs - s.startMs))
                .round();
      final int to = s.endMs <= endMs
          ? words.length
          : (words.length * (endMs - s.startMs) / (s.endMs - s.startMs))
                .round();
      if (to > from) {
        out.add((
          offsetMs: math.max(0, s.startMs - startMs),
          text: words.sublist(from, to).join(' '),
        ));
      }
    }
    if (hallucinate) {
      int n = 0;
      for (int b = startMs; b + 12000 <= endMs; b += 12000) {
        bool silent = true;
        for (int ms = b; ms < b + 12000 && silent; ms += 100) {
          if (track.speech(ms)) silent = false;
        }
        if (silent) {
          out.add((
            offsetMs: b - startMs,
            text: _hallucinations[n++ % _hallucinations.length],
          ));
        }
      }
      out.sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    }
    return out;
  }
}

/// Un trou du micro [gapStartMs]–[gapEndMs] (repère seul en base), la piste
/// [track] ; rend la note après le rattrapage par [GapBackfillRetry].
Future<({List<TranscriptSegmentEntity> lines, bool pendingLeft, int calls})>
_backfill(
  _Track track, {
  required int gapStartMs,
  required int gapEndMs,
  bool hallucinate = false,
  List<TranscriptSegmentEntity> stored = const <TranscriptSegmentEntity>[],
  String sessionId = _session,
}) async {
  final Directory dir = await Directory.systemTemp.createTemp('oats_silence_');
  final StreamController<ServerState> states =
      StreamController<ServerState>.broadcast();
  try {
    await _writeWav(
      '${dir.path}/${sessionId}_mic.wav',
      track,
      gapEndMs + 30000,
      1,
    );
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    for (final TranscriptSegmentEntity s in stored) {
      await repo.save(s);
    }
    if (stored.isEmpty) {
      await repo.save(
        TranscriptSegmentEntity(
          id: '${sessionId}_input_1',
          sessionId: sessionId,
          source: AudioSource.input,
          text: LiveTranscriptionService.gapMarkerText(gapStartMs, gapEndMs),
          timestampMs: gapStartMs,
          createdAt: DateTime(2026, 11, 25),
        ),
      );
    }
    final _Transcriber transcriber = _Transcriber(
      track,
      hallucinate: hallucinate,
    );
    final GapBackfillRetry retry = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: transcriber,
        transcripts: repo,
        isRecording: () => false,
      ),
      serverStates: states.stream,
      isRecording: () => false,
      recordingsDirectory: dir.path,
    );
    await retry.afterSession(sessionId);
    // Laisse aux reprises (une tentative qui avance repart d'elle-même) le
    // temps de finir, sans boucle : 2 s de vrai temps au plus.
    for (int i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await retry.dispose();
    return (
      lines: repo.of(AudioSource.input)
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs)),
      pendingLeft: File('${dir.path}/.backfill_pending.json').existsSync(),
      calls: transcriber.calls,
    );
  } finally {
    await states.close();
    await dir.delete(recursive: true);
  }
}

bool _isGapMarker(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

String _note(List<TranscriptSegmentEntity> lines) => lines
    .where((TranscriptSegmentEntity s) => !_isGapMarker(s))
    .map((TranscriptSegmentEntity s) => s.text)
    .join(' ');

void main() {
  // Trou 10–370 s ; parole 10,5–38 s et 340,5–368 s ; silence 0 de 40 à
  // 190 s, bruit de salle de 190 à 340 s.
  final _Track sixMinutes = _Track(
    <_Sentence>[
      for (final int at in <int>[10500, 20500, 30500, 340500, 350500, 360500])
        (startMs: at, endMs: at + 7500, text: _text(at ~/ 1000)),
    ],
    noise: const <(int, int)>[(190000, 340000)],
  );

  for (final bool hallucinate in <bool>[false, true]) {
    final String label = hallucinate
        ? 'le serveur hallucine sur le silence'
        : 'le serveur ne rend rien pour le silence';
    group('trou de 6 min, silence au milieu ($label)', () {
      late ({List<TranscriptSegmentEntity> lines, bool pendingLeft, int calls})
      r;
      setUpAll(() async {
        r = await _backfill(
          sixMinutes,
          gapStartMs: 10000,
          gapEndMs: 370000,
          hallucinate: hallucinate,
        );
      });

      test('chaque phrase revient une fois, celles d après le silence '
          'comprises', () {
        final String note = _note(r.lines);
        for (final _Sentence s in sixMinutes.sentences) {
          expect(
            s.text.allMatches(note).length,
            1,
            reason: '« ${s.text} » dans « $note »',
          );
        }
      });

      test('plus de repère sur le silence, rattrapage fini', () {
        expect(
          r.lines.where(_isGapMarker).map((s) => s.text).toList(),
          isEmpty,
        );
      });

      test('aucun texte halluciné rangé pour le silence', () {
        final List<String> invented = <String>[
          for (final TranscriptSegmentEntity s in r.lines)
            if (_hallucinations.any(s.text.contains))
              '${s.timestampMs} ${s.text}',
        ];
        expect(invented, isEmpty);
      });

      test('les tentatives s arrêtent et le fichier d attente est vidé', () {
        // 4 tranches de 100 s pour 361 s : quelques reprises au plus.
        expect(r.calls, lessThanOrEqualTo(12), reason: '${r.calls} appels');
        expect(r.pendingLeft, isFalse);
      });
    });
  }

  test('une phrase coupée par une borne de tranche après un long silence : '
      'aucun mot perdu, aucun doublon', () async {
    // Trou 10–250 s (plan 9 s : tranches 9–109, 109–209, 209–251) ; une
    // phrase 205–212,5 s chevauche la borne de 209 s, après 150 s de
    // silence ; une autre 104–111,5 s chevauche celle de 109 s.
    const List<int> at = <int>[10500, 104000, 205000, 240500];
    final _Track track = _Track(
      <_Sentence>[
        for (int i = 0; i < at.length; i++)
          (startMs: at[i], endMs: at[i] + 7500, text: _distinct[i]),
      ],
      noise: const <(int, int)>[(120000, 200000)],
    );
    final ({List<TranscriptSegmentEntity> lines, bool pendingLeft, int calls})
    r = await _backfill(track, gapStartMs: 10000, gapEndMs: 250000);
    final String note = _note(r.lines);
    for (final _Sentence s in track.sentences) {
      expect(note, contains(s.text), reason: 'mots perdus : « $note »');
      final String head = s.text.split(' ').take(3).join(' ');
      expect(head.allMatches(note).length, 1, reason: 'doublon : « $note »');
    }
    expect(r.lines.where(_isGapMarker), isEmpty);
  });

  test(
    'une phrase qui ressemble à la dernière rendue, au début d une tranche '
    'après 90 s de silence, est gardée (ce n est pas la fin d un voisin)',
    () async {
      // Mêmes mots sauf le numéro : « Phrase lue 10, … » puis, 94 s plus tard,
      // « Phrase lue 104, … » au début de la 2e tranche (coupée au silence à
      // 104 s).
      final _Track track = _Track(
        <_Sentence>[
          for (final int at in <int>[10500, 104000, 240500])
            (startMs: at, endMs: at + 7500, text: _text(at ~/ 1000)),
        ],
        noise: const <(int, int)>[(120000, 200000)],
      );
      final ({List<TranscriptSegmentEntity> lines, bool pendingLeft, int calls})
      r = await _backfill(track, gapStartMs: 10000, gapEndMs: 250000);
      final String note = _note(r.lines);
      for (final _Sentence s in track.sentences) {
        expect(note, contains(s.text), reason: 'perdue : « $note »');
      }
    },
  );

  test('coupure en direct pendant un long silence : après l arrêt et le '
      'rattrapage, aucun repère sur ce silence', () async {
    // Parole 0–30 s et 300–330 s (phrases 7,5 s toutes les 10 s), silence
    // (0) entre ; le micro est coupé de 60 à 200 s, en plein silence.
    final _Track track = _Track(<_Sentence>[
      for (final int at in <int>[500, 10500, 20500, 300500, 310500, 320500])
        (startMs: at, endMs: at + 7500, text: _text(at ~/ 1000)),
    ]);
    late List<TranscriptSegmentEntity> stored;
    late String sessionId;
    fakeAsync((FakeAsync async) {
      final FakeVoxServer server = FakeVoxServer();
      final FakeVoxSocket mic = FakeVoxSocket(server);
      final LiveServiceHarness h = LiveServiceHarness(
        async,
        remote: TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        ),
      )..start(outputEnabled: false);
      for (int id = 0; id < 3400; id++) {
        if (id == 600) {
          mic
            ..refusing = true
            ..drop();
        }
        if (id == 2000) mic.refusing = false;
        h.audio.emit(
          chunk(
            AudioSource.input,
            id,
            timestampMs: h.t0 + id * 100,
            voiced: track.speech(id * 100),
          ),
        );
        async.elapse(const Duration(milliseconds: 100));
      }
      h.stop();
      async.elapse(const Duration(minutes: 3));
      sessionId = h.session.id;
      stored = h.segments.store.values
          .where((TranscriptSegmentEntity x) => x.sessionId == sessionId)
          .toList();
    });
    final ({List<TranscriptSegmentEntity> lines, bool pendingLeft, int calls})
    r = stored.any(_isGapMarker)
        ? await _backfill(
            track,
            gapStartMs: 0,
            gapEndMs: 340000,
            stored: stored,
            sessionId: sessionId,
          )
        : (lines: stored, pendingLeft: false, calls: 0);
    final List<String> overSilence = <String>[
      for (final TranscriptSegmentEntity m in r.lines.where(_isGapMarker))
        if (markerRange(m.text) case final ({int startMs, int endMs}) x
            when x.startMs < 300000 && x.endMs > 30000)
          m.text,
    ];
    expect(overSilence, isEmpty);
    expect(
      r.lines.where(
        (TranscriptSegmentEntity s) => _hallucinations.any(s.text.contains),
      ),
      isEmpty,
    );
  });
}
