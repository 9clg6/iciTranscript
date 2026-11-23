import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #25, point 2, en séance (vraie source distante, sockets
// factices) : le repère provisoire de la coupure en cours et le repère
// final d'une perte de la même source qui se touchent ne laissent jamais
// deux repères ; un repère provisoire retiré (coupure finie sans perte) ne
// fusionne pas avec une perte PLUS TARDIVE (sinon de l'audio transcrit
// serait déclaré perdu).
void main() {
  late FakeAsync clock;
  late FakeVoxSocket mic;
  late LiveServiceHarness h;

  void setUpIn(FakeAsync async) {
    clock = async;
    final FakeVoxServer server = FakeVoxServer();
    mic = FakeVoxSocket(server);
    h = LiveServiceHarness(
      async,
      remote: TranscriptionRemoteDataSourceImpl(
        micClient: mic,
        systemClient: FakeVoxSocket(server),
      ),
    )..start(outputEnabled: false);
  }

  int id = 0;

  /// Parole continue du micro, [seconds] s, en 100 ms.
  void speak(int seconds, {void Function()? eachSecond}) {
    for (int i = 0; i < seconds * 10; i++, id++) {
      h.audio.emit(chunk(AudioSource.input, id, timestampMs: h.t0 + id * 100));
      clock.elapse(const Duration(milliseconds: 100));
      if (i % 10 == 9) eachSecond?.call();
    }
  }

  List<(int, int)> markerIntervals() {
    final List<(int, int)> out = <(int, int)>[];
    for (final TranscriptSegmentEntity s in h.segments.of(AudioSource.input)) {
      if (!s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix)) {
        continue;
      }
      final ({String markerId, AudioSource source, int startMs, int endMs})? p =
          GapBackfillService.plan(<TranscriptSegmentEntity>[s])
              .map(
                (g) => (
                  markerId: g.markerId,
                  source: g.source,
                  startMs: g.startMs,
                  endMs: g.endMs,
                ),
              )
              .firstOrNull;
      if (p != null) out.add((p.startMs, p.endMs));
    }
    return out;
  }

  bool overlapOrTouch(List<(int, int)> xs) {
    // Les intervalles du plan sont élargis de la marge des deux côtés.
    final int slack = 2 * GapBackfillService.margin.inMilliseconds;
    for (int i = 0; i < xs.length; i++) {
      for (int j = i + 1; j < xs.length; j++) {
        if (xs[i].$1 <= xs[j].$2 - slack && xs[j].$1 <= xs[i].$2 - slack) {
          return true;
        }
      }
    }
    return false;
  }

  test('coupure plus longue que le tampon : le repère provisoire et le '
      'repère final ne coexistent jamais en se recoupant', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      speak(10);
      mic
        ..refusing = true
        ..drop();
      final List<String> seen = <String>[];
      void check() {
        final List<(int, int)> xs = markerIntervals();
        if (overlapOrTouch(xs)) seen.add('${async.elapsed}: $xs');
      }

      speak(150, eachSecond: check); // le tampon déborde
      mic.refusing = false;
      speak(60, eachSecond: check); // reconnexion, renvoi, perte déclarée

      expect(seen, isEmpty, reason: 'repères qui se recoupent : $seen');
      expect(markerIntervals(), hasLength(1));
    });
  });

  test('un repère provisoire retiré ne fusionne pas avec une perte plus '
      'tardive', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      speak(10);
      mic
        ..refusing = true
        ..drop();
      speak(5); // courte coupure : repère provisoire
      mic.refusing = false;
      speak(30); // tout est livré : le provisoire est retiré
      expect(markerIntervals(), isEmpty, reason: 'rien n a été perdu');

      final int lateOutageMs = id * 100;
      mic
        ..refusing = true
        ..drop();
      speak(150);
      mic.refusing = false;
      speak(60);

      final List<(int, int)> xs = markerIntervals();
      expect(xs, hasLength(1));
      // La perte peut commencer avant la seconde coupure (la phrase en vol,
      // sans réponse, est perdue avec elle : 30 s au plus), jamais à la
      // première, toute livrée.
      expect(
        xs.single.$1 + GapBackfillService.margin.inMilliseconds,
        greaterThanOrEqualTo(lateOutageMs - 31000),
        reason: 'la perte ne remonte pas à la première coupure',
      );
      expect(
        xs.single.$1 + GapBackfillService.margin.inMilliseconds,
        greaterThan(45000),
      );
    });
  });
}
