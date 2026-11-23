import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Suivi du tour 10, point 2 — VISIBLE ET DURABLE TANT QUE ÇA DURE (sonde 9,
// S06 : serveur durablement lent, socket vivante). L'éviction a commencé à
// 202 s, la perte n'a été déclarée qu'à l'arrêt (540 s) : la plage perdue
// reste ouverte tant que le ralentissement dure.
//
// Banc : vraie source distante, serveur séquentiel à 0,3× le temps réel,
// micro seul, phrases de 7,5 s toutes les 10 s ; rétabli (3×) à 360 s.
//
// Attendu, avec la borne [_bound] = 5 s :
// - dans les 5 s qui suivent la première éviction, un repère de perte du
//   micro est À L'ÉCRAN (`segmentsStream`) et EN BASE ;
// - tant que la perte continue, c'est UN repère (pas un par morceau perdu)
//   dont la fin avance, et qui couvre tout ce qui a été perdu jusqu'à
//   5 s avant ;
// - l'app tuée pendant ce temps : le repère en base couvre ce qui a été
//   perdu (à 5 s près), et le rattrapage au relancement le rend ;
// - quand la plage se ferme enfin, c'est le MÊME repère (même id) qui porte
//   l'intervalle final.
const Duration _bound = Duration(seconds: 5);
const int _restoreId = 3600; // 360 s
const int _lastId = 4500;

bool _voiced(int id) => id % 100 < 75;

String _sentence(int k) =>
    'Phrase lue $k, le facteur répare la barrière numéro $k.';

final class _Run {
  _Run(this.session, this.firstEvictionMs);

  final String session;

  /// Heure de réunion (ms) de la première éviction.
  final int firstEvictionMs;

  /// Chunks voisés jamais transcrits.
  final List<int> lost = <int>[];

  /// Chunks reçus par le serveur (fin du jeu).
  final Set<int> received = <int>{};

  /// Par seconde de réunion : plus récent chunk reçu par le serveur.
  final Map<int, int> newestReceived = <int, int>{};

  /// Par seconde : lignes en direct (« Phrase numéro … ») à l'écran.
  final Map<int, Set<String>> liveOnScreen = <int, Set<String>>{};

  /// Par seconde de réunion : repères de perte du micro, à l'écran et en
  /// base (provisoire compris).
  final Map<int, List<TranscriptSegmentEntity>> screen =
      <int, List<TranscriptSegmentEntity>>{};
  final Map<int, List<TranscriptSegmentEntity>> store =
      <int, List<TranscriptSegmentEntity>>{};

  /// Base entière (cette séance) à chaque seconde : « l'app tuée ici ».
  final Map<int, List<TranscriptSegmentEntity>> disk =
      <int, List<TranscriptSegmentEntity>>{};

  late List<TranscriptSegmentEntity> finalMarkers;

  /// Jeté avant la seconde [s] : jamais reçu par le serveur alors qu'un
  /// chunk plus récent l'était déjà (le tampon l'a évincé sans l'envoyer).
  /// Pas « plus ancien que le plus ancien en attente » : l'audio évincé
  /// APRÈS envoi reste en vol et compte dans l'attente (à 252 s, l'attente
  /// commençait vers 80 s, la première perte à 113,9 s).
  List<int> lostBy(int s) {
    final int newest = newestReceived[s] ?? -1;
    return <int>[
      for (final int id in lost)
        if (!received.contains(id) && id < newest) id,
    ];
  }

  /// Première seconde où de l'audio a été jeté.
  int get firstDrop => newestReceived.keys
      .where((int s) => lostBy(s).isNotEmpty)
      .reduce((int a, int b) => a < b ? a : b);
}

bool _isGapMarker(TranscriptSegmentEntity s) =>
    s.source == AudioSource.input &&
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

bool _covers(TranscriptSegmentEntity marker, List<int> ids) {
  if (ids.isEmpty) return true;
  final ({int startMs, int endMs})? r = markerRange(marker.text);
  // Heures du repère à la seconde : 1 s de jeu de chaque côté.
  return r != null &&
      r.startMs <= ids.first * 100 + 1000 &&
      r.endMs + 1000 >= ids.last * 100 + 100;
}

_Run _play() {
  late _Run run;
  fakeAsync((FakeAsync async) {
    final FakeVoxServer server = FakeVoxServer(
      now: () => async.elapsed,
      speed: 0.3,
    );
    final FakeVoxSocket mic = FakeVoxSocket(server);
    final TranscriptionRemoteDataSourceImpl remote =
        TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        );
    final LiveServiceHarness h = LiveServiceHarness(async, remote: remote)
      ..start(outputEnabled: false);
    int? evictionMs;
    final Map<int, int> newest = <int, int>{};
    final Map<int, Set<String>> live = <int, Set<String>>{};
    final Map<int, List<TranscriptSegmentEntity>> screen =
        <int, List<TranscriptSegmentEntity>>{};
    final Map<int, List<TranscriptSegmentEntity>> store =
        <int, List<TranscriptSegmentEntity>>{};
    final Map<int, List<TranscriptSegmentEntity>> disk =
        <int, List<TranscriptSegmentEntity>>{};
    for (int id = 0; id < _lastId; id++) {
      if (id == _restoreId) server.speed = 3;
      h.audio.emit(
        chunk(
          AudioSource.input,
          id,
          timestampMs: h.t0 + id * 100,
          voiced: _voiced(id),
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      if (evictionMs == null &&
          remote.unacknowledgedAudio(AudioSource.input) >=
              const Duration(milliseconds: 119900)) {
        evictionMs = id * 100;
      }
      if (id % 10 == 9) {
        final int s = (id + 1) ~/ 10;
        if (mic.receivedIds.isNotEmpty) {
          newest[s] = mic.receivedIds.reduce((int a, int b) => a > b ? a : b);
        }
        live[s] = <String>{
          for (final TranscriptSegmentEntity x
              in h.transcription.segmentsStream.value)
            if (x.text.startsWith('Phrase numéro')) x.id,
        };
        screen[s] = h.transcription.segmentsStream.value
            .where(_isGapMarker)
            .toList();
        final List<TranscriptSegmentEntity> mine = h.segments.store.values
            .where((TranscriptSegmentEntity x) => x.sessionId == h.session.id)
            .toList();
        store[s] = mine.where(_isGapMarker).toList();
        disk[s] = mine;
      }
    }
    async.elapse(const Duration(seconds: 90));
    run = _Run(h.session.id, evictionMs ?? -1)
      ..newestReceived.addAll(newest)
      ..liveOnScreen.addAll(live)
      ..received.addAll(mic.receivedIds)
      ..screen.addAll(screen)
      ..store.addAll(store)
      ..disk.addAll(disk)
      ..finalMarkers = h.segments.store.values
          .where(
            (TranscriptSegmentEntity x) =>
                x.sessionId == h.session.id && _isGapMarker(x),
          )
          .toList();
    run.lost.addAll(<int>[
      for (int id = 0; id < _lastId; id++)
        if (_voiced(id) && !mic.transcribedIds.contains(id)) id,
    ]);
  });
  return run;
}

void main() {
  late _Run run;
  late int first; // seconde de la première éviction

  setUpAll(() {
    run = _play();
    first = (run.firstEvictionMs + 999) ~/ 1000;
  });

  test('le banc perd bien de l audio pendant le ralentissement', () {
    expect(run.firstEvictionMs, greaterThan(0));
    expect(run.lost, isNotEmpty);
    expect(run.lost.last * 100, lessThan(_restoreId * 100 + 60000));
  });

  test('dans les 5 s qui suivent la première éviction, un repère du micro '
      'est à l écran et en base', () {
    final int by = first + _bound.inSeconds;
    expect(
      run.screen[by],
      isNotEmpty,
      reason: 'à l écran à $by s (éviction à ${run.firstEvictionMs} ms)',
    );
    expect(
      run.store[by]!.where(
        (TranscriptSegmentEntity m) => !m.id.endsWith('_pending'),
      ),
      isNotEmpty,
      reason: 'en base, le même repère qu à l écran, à $by s',
    );
  });

  test('tant que la perte dure : un seul repère à l écran, dont la fin '
      'avance et qui couvre ce qui a été perdu', () {
    final List<String> bad = <String>[];
    int lastEnd = -1;
    for (int s = first + _bound.inSeconds; s < _restoreId ~/ 10; s += 10) {
      final List<TranscriptSegmentEntity> listed = run.screen[s]!;
      if (listed.length != 1) {
        bad.add('$s s : ${listed.length} repères à l écran');
        continue;
      }
      final List<int> lost = run.lostBy(s - _bound.inSeconds);
      if (!_covers(listed.single, lost)) {
        bad.add(
          '$s s : « ${listed.single.text} » ne couvre pas '
          '${lost.first * 100}–${lost.last * 100 + 100} ms',
        );
      }
      final int end = markerRange(listed.single.text)!.endMs;
      if (lost.isNotEmpty && end < lastEnd) bad.add('$s s : la fin recule');
      lastEnd = end;
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('tuée pendant la perte : le repère en base couvre ce qui a été perdu, '
      'et le plan du relancement le retranscrit', () {
    final List<String> bad = <String>[];
    for (int s = first + _bound.inSeconds; s < _restoreId ~/ 10; s += 10) {
      final List<int> lost = run.lostBy(s - _bound.inSeconds);
      if (lost.isEmpty) continue;
      if (!run.store[s]!.any((TranscriptSegmentEntity m) => _covers(m, lost))) {
        bad.add(
          '$s s : en base ${run.store[s]!.map((m) => m.text).toList()} ; '
          'perdu ${lost.first * 100}–${lost.last * 100 + 100} ms',
        );
        continue;
      }
      final List<BackfillGap> plan = GapBackfillService.plan(run.disk[s]!);
      final bool planned = plan.any(
        (BackfillGap g) =>
            g.source == AudioSource.input &&
            g.startMs <= lost.first * 100 &&
            g.endMs >= lost.last * 100 + 100,
      );
      if (!planned) bad.add('$s s : le plan ne couvre pas la perte');
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  /// Instants de « l'app tuée » : juste après la première perte, puis toutes
  /// les 8 s pendant le ralentissement, juste avant et juste après le
  /// rétablissement, et à la fin (plage fermée).
  List<int> killInstants() {
    final int drop = run.firstDrop;
    final int restore = _restoreId ~/ 10;
    return <int>{
      drop,
      drop + 1,
      for (int s = drop + 8; s < restore; s += 8) s,
      restore - 1,
      restore + 1,
      restore + 10,
      restore + 30,
      _lastId ~/ 10,
    }.where(run.disk.containsKey).toList()..sort();
  }

  final List<ProbeSentence> reference = <ProbeSentence>[
    for (int k = 0; k * 100 < _lastId; k++)
      (
        source: 'input',
        startMs: k * 10000,
        endMs: k * 10000 + 7500,
        text: _sentence(k),
      ),
  ];

  /// Lignes qui disent la phrase [k] : le texte rattrapé, ou la ligne en
  /// direct rangée à l'heure de la phrase.
  int said(List<TranscriptSegmentEntity> lines, int k) => lines
      .where(
        (TranscriptSegmentEntity l) =>
            l.text.contains('Phrase lue $k,') ||
            (l.text.startsWith('Phrase numéro') &&
                l.timestampMs >= k * 10000 - 500 &&
                l.timestampMs <= k * 10000 + 7500),
      )
      .length;

  test('le banc jette bien de l audio, assez tôt pour tuer l app pendant la '
      'perte', () {
    expect(run.firstDrop, lessThan(_restoreId ~/ 10 - 60));
    expect(killInstants().length, greaterThanOrEqualTo(16));
    // Le balayage voit de la perte à presque chaque instant.
    final List<int> withLoss = <int>[
      for (final int kill in killInstants())
        if (run.lostBy(kill - _bound.inSeconds).isNotEmpty) kill,
    ];
    expect(withLoss.length, greaterThanOrEqualTo(12), reason: '$withLoss');
  });

  test('tuée à chaque instant du ralentissement : la base, lue comme au '
      'relancement, a chaque phrase dite dans la note ou sous un repère', () {
    final List<String> bad = <String>[];
    for (final int kill in killInstants()) {
      final List<TranscriptSegmentEntity> disk = run.disk[kill]!
          .where((TranscriptSegmentEntity x) => x.source == AudioSource.input)
          .toList();
      for (
        int k = 0;
        k * 10000 + 7500 <= (kill - _bound.inSeconds) * 1000;
        k++
      ) {
        final bool covered = disk.any((TranscriptSegmentEntity m) {
          final ({int startMs, int endMs})? r = markerRange(m.text);
          return r != null &&
              r.startMs <= k * 10000 + 1000 &&
              r.endMs + 1000 >= k * 10000 + 7500;
        });
        if (!covered && said(disk, k) == 0) {
          bad.add('tuée à $kill s : phrase $k');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test(
    'tuée à chaque instant du ralentissement : le rattrapage au '
    'relancement rend chaque phrase perdue, et chaque phrase une fois',
    () async {
      final List<String> bad = <String>[];
      for (final int kill in killInstants()) {
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
        final Set<int> lostSentences = <int>{
          for (final int id in run.lostBy(kill - _bound.inSeconds)) id ~/ 100,
        };
        for (final int k in lostSentences) {
          if (!lines.any((l) => l.text.contains('Phrase lue $k,'))) {
            bad.add('tuée à $kill s : phrase perdue $k non rendue');
          }
        }
        for (
          int k = 0;
          k * 10000 + 7500 <= (kill - _bound.inSeconds) * 1000;
          k++
        ) {
          final int n = said(lines, k);
          if (n != 1) bad.add('tuée à $kill s : phrase $k dite $n fois');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    },
  );

  test('pendant la réunion, une ligne en direct affichée n est jamais retirée '
      'de l écran par le repère qui grandit', () {
    final List<int> seconds = run.liveOnScreen.keys.toList()..sort();
    final Set<String> seen = <String>{};
    final List<String> bad = <String>[];
    for (final int s in seconds) {
      final Set<String> now = run.liveOnScreen[s]!;
      for (final String id in seen.difference(now)) {
        bad.add('$s s : $id retirée de l écran');
      }
      seen.addAll(now);
    }
    expect(seen, isNotEmpty);
    expect(bad.take(10).toList(), isEmpty, reason: '${bad.length} retraits');
  });

  test('quand la plage se ferme : le même repère (même id) porte '
      'l intervalle final, seul', () {
    final List<TranscriptSegmentEntity> shown =
        run.screen[first + _bound.inSeconds]!;
    expect(shown, isNotEmpty);
    expect(run.finalMarkers, hasLength(1), reason: 'un repère pour la perte');
    expect(run.finalMarkers.single.id, shown.first.id);
    expect(_covers(run.finalMarkers.single, run.lost), isTrue);
  });
}
