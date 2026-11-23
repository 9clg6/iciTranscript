import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../fixtures/probe10_sequences.dart';
import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Sonde 10 contre le VRAI serveur (proxy à 0,6×, svc_S06.jsonl et svc_K) :
// les specs « visible et durable » du tour 10 passaient, le réel non.
//
// Séquence réelle (S06), rejouée telle quelle :
// - 0–99,8 s : socket vivante, serveur lent (dernier `done` micro 99,4 s) ;
// - 99,8 s : le serveur ferme les DEUX sockets ; reconnexions à 100,4,
//   110,4, 130,4, 170,4, 230,4, 290,4, 350,4, 410,4 s : le proxy accepte,
//   la poignée de main n'aboutit jamais avant la borne (10, 20, 40, 60 s) ;
// - rien n'est envoyé (en attente = non envoyé dès 105 s) ; le tampon
//   atteint 120 s à ~202 s (micro), ~219 s (système) et jette l'audio ;
// - seul repère en base : le PROVISOIRE (`_pending`, dès 80 s), dont le
//   DÉBUT suit l'éviction (micro 0:59 → 1:36 à 239 s) : l'audio jeté sort
//   du repère ; rien à l'écran avant 660 s (après l'arrêt et sa vidange) ;
// - 460–480 s : refus ; 480 s : connexion acceptée, serveur muet.
//
// Pourquoi le banc d'avant l'avait manqué : il ralentissait le SERVEUR sur
// une socket VIVANTE (les `done` continuaient d'arriver, la perte passait
// par l'acquittement) ; le réel est une COUPURE qui ne se referme pas :
// poignées de main sans fin, aucun message, la perte reste dans le tampon
// de la coupure et n'est déclarée qu'à une reconnexion qui ne vient pas.
//
// Attendu :
// 1. à chaque seconde, la base vérifie l'invariant : chaque phrase finie
//    depuis 60 s (texte en vol exclu) est dans la note ou sous un repère ; l'audio déjà jeté
//    reste couvert (le début du repère ne dépasse jamais le premier audio
//    jeté tant qu'il n'est pas rendu) ;
// 2. K : la base laissée par l'arrêt brutal à 300 s, puis le rattrapage au
//    relancement (transcripteur sain) : chaque phrase une fois ;
// 3. écran : dans les 5 s qui suivent la première éviction d'une source,
//    un repère de cette source est sur le flux, pendant la réunion.
const Duration _bound = Duration(seconds: 5);

/// L'invariant vaut pour les phrases finies depuis 60 s : avant, le texte
/// d'une phrase en vol peut encore arriver (30 s d'audio en vol, serveur à
/// 0,6× : 50 s). L'audio jeté a toujours plus de 120 s : il est vérifié.
const Duration _settled = Duration(seconds: 60);
const int _closeAt = 998; // 99,8 s : le serveur ferme les sockets
const int _refuseAt = 4600;
const int _openAt = 4800;
const int _endAt = 5400; // 540 s : arrêt

bool _voiced(String source, int id) => probe10Live60Reference.any(
  (ProbeSentence r) =>
      r.source == source && id * 100 >= r.startMs && id * 100 < r.endMs,
);

final class _Replay {
  final Map<AudioSource, int> firstEviction = <AudioSource, int>{};
  final Map<int, List<TranscriptSegmentEntity>> store =
      <int, List<TranscriptSegmentEntity>>{};
  final Map<int, List<TranscriptSegmentEntity>> screen =
      <int, List<TranscriptSegmentEntity>>{};
}

bool _isMarker(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
    LiveTranscriptionService.isUntranscribedMarker(s.text);

_Replay _play() {
  final _Replay out = _Replay();
  fakeAsync((FakeAsync async) {
    final FakeVoxServer server = FakeVoxServer(
      now: () => async.elapsed,
      speed: 0.6,
    );
    final FakeVoxSocket mic = FakeVoxSocket(server);
    final FakeVoxSocket sys = FakeVoxSocket(server);
    final TranscriptionRemoteDataSourceImpl remote =
        TranscriptionRemoteDataSourceImpl(micClient: mic, systemClient: sys);
    final LiveServiceHarness h = LiveServiceHarness(async, remote: remote)
      ..start();
    for (int id = 0; id < _endAt; id++) {
      if (id == _closeAt) {
        for (final FakeVoxSocket s in <FakeVoxSocket>[mic, sys]) {
          s
            ..hanging = true
            ..drop();
        }
      }
      if (id == _refuseAt) {
        for (final FakeVoxSocket s in <FakeVoxSocket>[mic, sys]) {
          s
            ..hanging = false
            ..refusing = true;
        }
      }
      if (id == _openAt) {
        for (final FakeVoxSocket s in <FakeVoxSocket>[mic, sys]) {
          s
            ..refusing = false
            ..autoReply = false; // serveur muet
        }
      }
      for (final (AudioSource source, String name) in <(AudioSource, String)>[
        (AudioSource.input, 'input'),
        (AudioSource.output, 'output'),
      ]) {
        h.audio.emit(
          chunk(
            source,
            id,
            timestampMs: h.t0 + id * 100,
            voiced: _voiced(name, id),
          ),
        );
      }
      async.elapse(const Duration(milliseconds: 100));
      for (final AudioSource source in AudioSource.values) {
        if (!out.firstEviction.containsKey(source) &&
            remote.unacknowledgedAudio(source) >=
                const Duration(milliseconds: 119900)) {
          out.firstEviction[source] = id * 100;
        }
      }
      if (id % 10 == 9) {
        final int s = (id + 1) ~/ 10;
        out.store[s] = h.segments.store.values
            .where((TranscriptSegmentEntity x) => x.sessionId == h.session.id)
            .toList();
        out.screen[s] = h.transcription.segmentsStream.value
            .where(_isMarker)
            .toList();
      }
    }
  });
  return out;
}

/// Ligne en direct de la phrase [r] : rangée à son heure (fenêtre de la
/// phrase), ou un texte qui en a au moins 60 % des mots.
bool _said(List<TranscriptSegmentEntity> lines, ProbeSentence r) => lines.any(
  (TranscriptSegmentEntity l) =>
      l.source == sourceOf(r.source) &&
      !_isMarker(l) &&
      ((l.timestampMs >= r.startMs - 500 &&
              l.timestampMs <= r.startMs + 1500) ||
          (l.timestampMs >= r.startMs - 10000 &&
              l.timestampMs <= r.endMs + 2000 &&
              coverage(r.text, l.text) >= 0.6)),
);

bool _covered(List<TranscriptSegmentEntity> lines, ProbeSentence r) =>
    lines.any((TranscriptSegmentEntity m) {
      final ({int startMs, int endMs})? x = markerRange(m.text);
      return m.source == sourceOf(r.source) &&
          x != null &&
          x.startMs <= r.startMs + 1000 &&
          x.endMs + 1000 >= r.endMs;
    });

void main() {
  late _Replay replay;

  setUpAll(() => replay = _play());

  test('le rejeu suit la séquence réelle : plus rien d envoyé après 99,8 s, '
      'éviction vers 200 s', () {
    final int? mic = replay.firstEviction[AudioSource.input];
    expect(mic, isNotNull);
    expect(mic!, inInclusiveRange(170000, 230000)); // réel : ~202 s
  });

  test('S06 rejoué : à chaque seconde, chaque phrase finie est dans la note ou '
      'sous un repère en base (l audio jeté reste couvert)', () {
    final List<String> bad = <String>[];
    final List<int> seconds = replay.store.keys.toList()..sort();
    for (final int s in seconds) {
      final List<TranscriptSegmentEntity> lines = replay.store[s]!;
      for (final ProbeSentence r in probe10Live60Reference) {
        if (r.endMs > s * 1000 - _settled.inMilliseconds) continue;
        if (!_said(lines, r) && !_covered(lines, r)) {
          bad.add('$s s : ${r.source} ${r.startMs} ms');
        }
      }
    }
    expect(
      bad.take(12).toList(),
      isEmpty,
      reason:
          '${bad.length} manques, premier à ${bad.isEmpty ? '-' : bad.first}',
    );
  });

  test('S06 rejoué : dans les 5 s qui suivent la première éviction, un repère '
      'de la source est à l écran', () {
    for (final MapEntry<AudioSource, int> e in replay.firstEviction.entries) {
      final int by = (e.value + 999) ~/ 1000 + _bound.inSeconds;
      expect(
        replay.screen[by]!.where(
          (TranscriptSegmentEntity m) => m.source == e.key,
        ),
        isNotEmpty,
        reason: '${e.key.name} : éviction à ${e.value} ms, rien à $by s',
      );
    }
  });

  test('K : base de l arrêt brutal à 300 s, rattrapage au relancement : '
      'chaque phrase une fois', () async {
    final InMemoryTranscriptRepository repo = await runRecordedBackfill(
      RecordedSession(
        name: 'K (sonde 10)',
        sessionId: probe10KSessionId,
        stored: <TranscriptSegmentEntity>[
          for (final ProbeSegment s in probe10KSegments)
            TranscriptSegmentEntity(
              id: s.id,
              sessionId: probe10KSessionId,
              source: sourceOf(s.source),
              text: s.text,
              timestampMs: s.timestampMs,
              createdAt: DateTime(2026, 11, 25),
            ),
          for (final ({String id, String source, String text}) m
              in probe10KMarkers)
            TranscriptSegmentEntity(
              id: m.id,
              sessionId: probe10KSessionId,
              source: sourceOf(m.source),
              text: m.text,
              timestampMs: markerRange(m.text)!.startMs,
              createdAt: DateTime(2026, 11, 25),
            ),
        ],
        recovered: const <RecoveredPiece>[],
        recordedStarts: const <RecordedInterval>[],
        reference: probe10Live60Reference,
      ),
    );
    final List<String> bad = <String>[];
    for (final ProbeSentence r in probe10Live60Reference) {
      if (r.endMs > 295000) continue;
      final List<TranscriptSegmentEntity> lines = repo
          .of(sourceOf(r.source))
          .where((TranscriptSegmentEntity l) => !_isMarker(l))
          .toList();
      final int n = lines
          .where(
            (TranscriptSegmentEntity l) =>
                l.timestampMs >= r.startMs - 10000 &&
                l.timestampMs <= r.endMs + 2000 &&
                coverage(r.text, l.text) >= 0.6,
          )
          .length;
      if (n != 1) bad.add('${r.source} ${r.startMs} ms : $n fois');
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
