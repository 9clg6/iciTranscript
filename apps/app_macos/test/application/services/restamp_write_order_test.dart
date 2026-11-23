import 'dart:async';

import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 9, point 3 (revue de `_onAudioGap`) : une phrase scellée est rangée,
// puis re-rangée à l'heure du début de la perte ; la seconde écriture n'est
// pas chaînée après la première. Si la première (heure d'arrivée) se
// termine après, elle écrase la bonne heure.
//
// Dépôt lent : chaque écriture attend qu'on la libère ; on les libère dans
// l'ordre inverse. Le segment rangé doit finir à l'heure du début de la
// perte, jamais à l'heure d'arrivée, quel que soit l'ordre de fin.
void main() {
  for (final bool lastFirst in <bool>[true, false]) {
    test('la phrase scellée finit à l heure de la perte (écritures libérées '
        '${lastFirst ? 'de la dernière à la première' : 'dans l ordre'})', () {
      fakeAsync((FakeAsync async) {
        final _SlowRepository repo = _SlowRepository();
        final LiveServiceHarness h = LiveServiceHarness(async, segments: repo)
          ..start();
        async.elapse(const Duration(seconds: 306));
        h.fakeRemote.emitDelta(
          AudioSource.input,
          'La boulangère a nettoyé le kiosque à journaux malgré le vent '
          'froid, puis la',
        );
        async.elapse(const Duration(seconds: 3)); // provisoire : en attente
        h.fakeRemote.emitControl(AudioSource.input, utteranceLostEventType);
        async.elapse(const Duration(milliseconds: 100)); // scellée : en attente
        h.fakeRemote.emitGap(
          AudioGap(
            source: AudioSource.input,
            startMs: h.t0 + 148048,
            endMs: h.t0 + 165000,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        repo.releaseAll(lastFirst: lastFirst);
        async.elapse(const Duration(seconds: 1));
        repo.releaseAll(lastFirst: lastFirst); // écritures chaînées ensuite
        async.elapse(const Duration(seconds: 1));
        repo.releaseAll(lastFirst: lastFirst);
        async.elapse(const Duration(seconds: 1));

        final TranscriptSegmentEntity sealed = repo.store.values.singleWhere(
          (TranscriptSegmentEntity s) => s.text.startsWith('La boulangère'),
        );
        expect(
          sealed.timestampMs,
          148048,
          reason: 'heure du début de la perte',
        );
      });
    });
  }
}

/// Dépôt dont chaque écriture attend d'être libérée.
class _SlowRepository extends InMemoryTranscriptRepository {
  final List<Completer<void>> _held = <Completer<void>>[];

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async {
    final Completer<void> gate = Completer<void>();
    _held.add(gate);
    await gate.future;
    return super.save(segment);
  }

  void releaseAll({required bool lastFirst}) {
    final List<Completer<void>> now = List<Completer<void>>.of(_held);
    _held.clear();
    for (final Completer<void> c in lastFirst ? now.reversed : now) {
      c.complete();
    }
  }
}
