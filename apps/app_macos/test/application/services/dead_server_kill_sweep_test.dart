import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Suite de la sonde 10 : la socket FERMÉE, pas seulement un serveur lent.
//
// 1. Cas simple : serveur mort (socket fermée, chaque reconnexion refusée
//    ou sans fin) dès la 2e minute d'une réunion de 6 min ; arrêt brutal
//    simulé toutes les 10 s de 2:10 à 6:00. À chaque arrêt, la base vérifie
//    l'invariant (chaque phrase finie dans la note ou sous un repère) et le
//    rattrapage au relancement (transcripteur sain) rend chaque phrase une
//    fois.
// 2. Le balayage de 16 instants du ralentissement, socket FERMÉE : coupure
//    à 60 s, poignées de main sans fin jusqu'à 360 s, puis reconnexion.
//
// Micro seul ; phrase k de 10k s à 10k + 7,5 s ; serveur sain : `done` en
// 400 ms (le texte d'une phrase finie depuis 5 s est arrivé).
const Duration _bound = Duration(seconds: 5);

String _sentence(int k) => 'Phrase lue $k, le facteur répare la barrière $k.';

bool _voiced(int id) => id % 100 < 75;

enum _Dead { refused, hanging }

final class _Run {
  _Run(this.session);

  final String session;
  int? firstEvictionS;

  /// Base entière (cette séance), à chaque seconde : « l'app tuée ici ».
  final Map<int, List<TranscriptSegmentEntity>> disk =
      <int, List<TranscriptSegmentEntity>>{};
}

/// Réunion de [endId] × 100 ms ; socket fermée à [closeId], reconnexions
/// [dead] jusqu'à [reopenId] (null : jamais).
_Run _play({
  required int closeId,
  required int endId,
  required _Dead dead,
  int? reopenId,
}) {
  late _Run run;
  fakeAsync((FakeAsync async) {
    final FakeVoxServer server = FakeVoxServer();
    final FakeVoxSocket mic = FakeVoxSocket(server);
    final TranscriptionRemoteDataSourceImpl remote =
        TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        );
    final LiveServiceHarness h = LiveServiceHarness(async, remote: remote)
      ..start(outputEnabled: false);
    run = _Run(h.session.id);
    for (int id = 0; id < endId; id++) {
      if (id == closeId) {
        if (dead == _Dead.refused) {
          mic.refusing = true;
        } else {
          mic.hanging = true;
        }
        mic.drop();
      }
      if (id == reopenId) {
        mic
          ..refusing = false
          ..hanging = false;
      }
      h.audio.emit(
        chunk(
          AudioSource.input,
          id,
          timestampMs: h.t0 + id * 100,
          voiced: _voiced(id),
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      if (run.firstEvictionS == null &&
          remote.unacknowledgedAudio(AudioSource.input) >=
              const Duration(milliseconds: 119900)) {
        run.firstEvictionS = (id + 10) ~/ 10;
      }
      if (id % 10 == 9) {
        run.disk[(id + 1) ~/ 10] = h.segments.store.values
            .where((TranscriptSegmentEntity x) => x.sessionId == h.session.id)
            .toList();
      }
    }
  });
  return run;
}

bool _isMarker(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
    LiveTranscriptionService.isUntranscribedMarker(s.text);

/// Lignes qui disent la phrase [k] : le texte rattrapé, ou la ligne en
/// direct rangée à son heure.
int _said(List<TranscriptSegmentEntity> lines, int k) => lines
    .where(
      (TranscriptSegmentEntity l) =>
          !_isMarker(l) &&
          (l.text.contains('Phrase lue $k,') ||
              (l.text.startsWith('Phrase numéro') &&
                  l.timestampMs >= k * 10000 - 500 &&
                  l.timestampMs <= k * 10000 + 7500)),
    )
    .length;

bool _covered(List<TranscriptSegmentEntity> lines, int k) =>
    lines.any((TranscriptSegmentEntity m) {
      final ({int startMs, int endMs})? r = markerRange(m.text);
      return r != null &&
          r.startMs <= k * 10000 + 1000 &&
          r.endMs + 1000 >= k * 10000 + 7500;
    });

/// Phrases finies [_bound] avant l'arrêt à [kill] s.
Iterable<int> _finished(int kill) sync* {
  for (int k = 0; k * 10000 + 7500 <= (kill - _bound.inSeconds) * 1000; k++) {
    yield k;
  }
}

List<String> _invariant(_Run run, List<int> kills) => <String>[
  for (final int kill in kills)
    for (final int k in _finished(kill))
      if (_said(run.disk[kill]!, k) == 0 && !_covered(run.disk[kill]!, k))
        'tuée à $kill s : phrase $k ni dans la note ni sous un repère',
];

Future<List<String>> _relaunch(_Run run, List<int> kills, int endId) async {
  final List<ProbeSentence> reference = <ProbeSentence>[
    for (int k = 0; k * 100 < endId; k++)
      (
        source: 'input',
        startMs: k * 10000,
        endMs: k * 10000 + 7500,
        text: _sentence(k),
      ),
  ];
  final List<String> bad = <String>[];
  for (final int kill in kills) {
    final InMemoryTranscriptRepository repo = await runRecordedBackfill(
      RecordedSession(
        name: 'tuée à $kill s',
        sessionId: run.session,
        stored: run.disk[kill]!,
        recovered: const <RecoveredPiece>[],
        recordedStarts: const <RecordedInterval>[],
        reference: reference,
      ),
    );
    final List<TranscriptSegmentEntity> lines = repo.of(AudioSource.input);
    for (final int k in _finished(kill)) {
      final int n = _said(lines, k);
      if (n != 1) bad.add('tuée à $kill s : phrase $k dite $n fois');
    }
  }
  return bad;
}

String _summary(List<String> bad) =>
    '${bad.length} écarts, dont :\n${bad.take(8).join('\n')}';

void main() {
  const int endId = 3600; // 6 min
  final List<int> kills = <int>[for (int s = 130; s <= 360; s += 10) s];

  for (final _Dead dead in _Dead.values) {
    group('serveur mort dès 2:00 (reconnexions ${dead.name})', () {
      late _Run run;
      setUpAll(() => run = _play(closeId: 1200, endId: endId + 1, dead: dead));

      test('tuée toutes les 10 s de 2:10 à 6:00 : chaque phrase finie dans la '
          'note ou sous un repère', () {
        final List<String> bad = _invariant(run, kills);
        expect(bad, isEmpty, reason: _summary(bad));
      });

      test('tuée toutes les 10 s de 2:10 à 6:00 : le rattrapage au relancement '
          'rend chaque phrase une fois', () async {
        final List<String> bad = await _relaunch(run, kills, endId);
        expect(bad, isEmpty, reason: _summary(bad));
      }, timeout: const Timeout(Duration(minutes: 5)));
    });
  }

  group('balayage de 16 instants, socket FERMÉE de 60 s à 360 s', () {
    const int last = 4500;
    late _Run run;
    late List<int> sweep;
    setUpAll(() {
      run = _play(
        closeId: 600,
        reopenId: 3600,
        endId: last,
        dead: _Dead.hanging,
      );
      final int first = run.firstEvictionS ?? 200;
      sweep = <int>{
        first,
        first + 1,
        for (int s = first + 8; s < 360; s += 8) s,
        359,
        361,
        370,
        390,
        last ~/ 10,
      }.where(run.disk.containsKey).toList()..sort();
    });

    test(
      'le banc jette de l audio pendant la coupure, 16 instants au moins',
      () {
        expect(run.firstEvictionS, isNotNull);
        expect(run.firstEvictionS!, lessThan(300));
        expect(sweep.length, greaterThanOrEqualTo(16));
      },
    );

    test('à chaque instant : chaque phrase finie dans la note ou sous un '
        'repère', () {
      final List<String> bad = _invariant(run, sweep);
      expect(bad, isEmpty, reason: _summary(bad));
    });

    test('à chaque instant : le rattrapage au relancement rend chaque phrase '
        'une fois', () async {
      final List<String> bad = await _relaunch(run, sweep, last);
      expect(bad, isEmpty, reason: _summary(bad));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
