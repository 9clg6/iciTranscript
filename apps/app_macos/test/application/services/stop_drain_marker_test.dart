import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Régression de la sonde 11 (A2, vrai serveur, svc_A2.jsonl). Séquence
// réelle, rejouée telle quelle :
// - 20 s : réponses retardées de 40 s ; 60 s : coupure, reconnexions
//   refusées ; 61 s : retard 0 ; 210 s : le proxy rouvre (reconnexion à
//   215,6 s) ; 230 s : réponses retardées de 30 s jusqu'à la fin ;
// - un repère par source, qui grandit : micro 0:20–5:00, système
//   0:18–4:59 à l'arrêt (300 s) ;
// - l'attente de l'arrêt atteint sa borne (120 s, à 420 s) avec ~140 s
//   d'audio sans réponse ; le repère RÉTRÉCIT alors aux pertes déjà
//   déclarées (micro 0:20–1:14, système 0:18–2:16) : la fin sans réponse
//   (241–294 s, micro 27–31, système 26–31) n'est sous aucun repère, le
//   rattrapage ne la rend jamais. Perte silencieuse.
//
// Attendu :
// 1. arrêt dont l'attente finit à sa borne, par « Passer »
//    (`skipFinalising`, aussi la voie de Quitter depuis le panneau) ou par
//    une socket fermée pendant l'attente : à chaque seconde, de l'arrêt à
//    la fin de l'attente et après, la base vérifie l'invariant (chaque
//    phrase dite avant l'arrêt dans la note ou sous un repère) ; le
//    rattrapage d'après réunion rend chaque phrase une fois ;
// 2. le repère ne rétrécit jamais en deçà de l'audio sans réponse ni
//    rattrapé, quelle que soit la fin de l'attente ;
// 3. arrêt brutal à au moins 10 instants pendant l'attente : la base
//    laissée, rattrapée au relancement, rend chaque phrase une fois.
const int _stopId = 3000; // 300 s

enum _End { limit, skip, socketClosed }

bool _voiced(String source, int id) => probeReference.any(
  (ProbeSentence r) =>
      r.source == source && id * 100 >= r.startMs && id * 100 < r.endMs,
);

final class _Replay {
  _Replay(this.session);

  final String session;

  /// Base de la séance, à chaque seconde après l'arrêt.
  final Map<int, List<TranscriptSegmentEntity>> disk =
      <int, List<TranscriptSegmentEntity>>{};

  /// Chunks voisés sans réponse, à chaque seconde après l'arrêt.
  final Map<int, Map<AudioSource, List<int>>> unanswered =
      <int, Map<AudioSource, List<int>>>{};
}

_Replay _play(_End end) {
  late _Replay out;
  fakeAsync((FakeAsync async) {
    // File unique des deux sources, 1,5× le temps réel : le réel avançait
    // d'environ 105 s d'audio par source en 120 s d'attente (de la phrase 14
    // à la 25 entre 300 et 420 s).
    final FakeVoxServer server = FakeVoxServer(
      now: () => async.elapsed,
      speed: 1.5,
    );
    final FakeVoxSocket mic = FakeVoxSocket(server);
    final FakeVoxSocket sys = FakeVoxSocket(server);
    final TranscriptionRemoteDataSourceImpl remote =
        TranscriptionRemoteDataSourceImpl(micClient: mic, systemClient: sys);
    final LiveServiceHarness h = LiveServiceHarness(async, remote: remote)
      ..start();
    out = _Replay(h.session.id);
    final List<int> spokenMic = <int>[];
    final List<int> spokenSys = <int>[];
    void snapshot(int s) {
      out.disk[s] = h.segments.store.values
          .where((TranscriptSegmentEntity x) => x.sessionId == h.session.id)
          .toList();
      out.unanswered[s] = <AudioSource, List<int>>{
        AudioSource.input: <int>[
          for (final int id in spokenMic)
            if (!mic.transcribedIds.contains(id)) id,
        ],
        AudioSource.output: <int>[
          for (final int id in spokenSys)
            if (!sys.transcribedIds.contains(id)) id,
        ],
      };
    }

    for (int id = 0; id < _stopId; id++) {
      if (id == 200) server.lag = const Duration(seconds: 40);
      if (id == 600) {
        for (final FakeVoxSocket s in <FakeVoxSocket>[mic, sys]) {
          s
            ..refusing = true
            ..drop();
        }
      }
      if (id == 610) server.lag = Duration.zero;
      if (id == 2100) {
        mic.refusing = false;
        sys.refusing = false;
      }
      if (id == 2300) server.lag = const Duration(seconds: 30);
      for (final (AudioSource source, String name, List<int> spoken)
          in <(AudioSource, String, List<int>)>[
            (AudioSource.input, 'input', spokenMic),
            (AudioSource.output, 'output', spokenSys),
          ]) {
        final bool v = _voiced(name, id);
        if (v) spoken.add(id);
        h.audio.emit(
          chunk(source, id, timestampMs: h.t0 + id * 100, voiced: v),
        );
      }
      async.elapse(const Duration(milliseconds: 100));
    }
    unawaited(h.service.stopTranscription());
    for (int s = _stopId ~/ 10; s <= 500; s++) {
      if (s == 330) {
        if (end == _End.skip) h.service.skipFinalising();
        if (end == _End.socketClosed) {
          for (final FakeVoxSocket x in <FakeVoxSocket>[mic, sys]) {
            x
              ..refusing = true
              ..drop();
          }
        }
      }
      snapshot(s);
      async.elapse(const Duration(seconds: 1));
    }
  });
  return out;
}

bool _isMarker(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
    LiveTranscriptionService.isUntranscribedMarker(s.text);

/// Phrases dites avant l'arrêt (et finies 5 s avant).
final List<ProbeSentence> _spoken = <ProbeSentence>[
  for (final ProbeSentence r in probeReference)
    if (r.endMs <= _stopId * 100 - 5000) r,
];

/// Lignes qui disent [r] : texte rattrapé (référence) ou ligne en direct
/// rangée à son heure.
int _said(List<TranscriptSegmentEntity> lines, ProbeSentence r) => lines
    .where(
      (TranscriptSegmentEntity l) =>
          l.source == sourceOf(r.source) &&
          !_isMarker(l) &&
          (l.text.contains(r.text) ||
              (l.text.startsWith('Phrase numéro') &&
                  l.timestampMs >= r.startMs - 500 &&
                  l.timestampMs <= r.startMs + 1500)),
    )
    .length;

bool _covers(
  List<TranscriptSegmentEntity> lines,
  AudioSource source,
  int fromMs,
  int toMs,
) => lines.any((TranscriptSegmentEntity m) {
  final ({int startMs, int endMs})? x = markerRange(m.text);
  return m.source == source &&
      x != null &&
      x.startMs <= fromMs + 1000 &&
      x.endMs + 1000 >= toMs;
});

String _summary(List<String> bad) =>
    '${bad.length} écarts, dont :\n${bad.take(8).join('\n')}';

Future<List<String>> _backfillOnce(_Replay replay, int at, String label) async {
  final InMemoryTranscriptRepository repo = await runRecordedBackfill(
    RecordedSession(
      name: label,
      sessionId: replay.session,
      stored: replay.disk[at]!,
      recovered: const <RecoveredPiece>[],
      recordedStarts: const <RecordedInterval>[],
    ),
  );
  final List<TranscriptSegmentEntity> lines = <TranscriptSegmentEntity>[
    ...repo.of(AudioSource.input),
    ...repo.of(AudioSource.output),
  ];
  return <String>[
    for (final ProbeSentence r in _spoken)
      if (_said(lines, r) != 1)
        '$label : ${r.source} ${r.startMs} ms dite ${_said(lines, r)} fois',
  ];
}

void main() {
  for (final _End end in _End.values) {
    group('attente de l arrêt finie par ${end.name}', () {
      late _Replay replay;
      setUpAll(() => replay = _play(end));

      test('à chaque seconde de l arrêt et après : chaque phrase dite dans la '
          'note ou sous un repère', () {
        final List<String> bad = <String>[];
        final List<int> seconds = replay.disk.keys.toList()..sort();
        for (final int s in seconds) {
          final List<TranscriptSegmentEntity> lines = replay.disk[s]!;
          for (final ProbeSentence r in _spoken) {
            if (_said(lines, r) == 0 &&
                !_covers(lines, sourceOf(r.source), r.startMs, r.endMs)) {
              bad.add('$s s : ${r.source} ${r.startMs} ms');
            }
          }
        }
        expect(bad, isEmpty, reason: _summary(bad));
      });

      test('le repère ne rétrécit jamais en deçà de l audio sans réponse', () {
        final List<String> bad = <String>[];
        final List<int> seconds = replay.unanswered.keys.toList()..sort();
        for (final int s in seconds) {
          for (final MapEntry<AudioSource, List<int>> e
              in replay.unanswered[s]!.entries) {
            for (final int id in e.value) {
              if (id * 100 > _stopId * 100 - 5000) continue;
              if (!_covers(replay.disk[s]!, e.key, id * 100, id * 100 + 100)) {
                bad.add('$s s : ${e.key.name} ${id * 100} ms sans réponse');
                break;
              }
            }
          }
        }
        expect(bad, isEmpty, reason: _summary(bad));
      });

      test(
        'après l attente, le rattrapage rend chaque phrase une fois',
        () async {
          final List<String> bad = await _backfillOnce(replay, 500, 'fin');
          expect(bad, isEmpty, reason: _summary(bad));
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  }

  test('arrêt brutal à 13 instants de l attente : la base laissée, rattrapée '
      'au relancement, rend chaque phrase une fois', () async {
    final _Replay replay = _play(_End.limit);
    final List<String> bad = <String>[
      for (final int kill in <int>[
        301,
        305,
        315,
        330,
        345,
        360,
        375,
        390,
        405,
        415,
        419,
        421,
        425,
      ])
        ...await _backfillOnce(replay, kill, 'tuée à $kill s'),
    ];
    expect(bad, isEmpty, reason: _summary(bad));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
