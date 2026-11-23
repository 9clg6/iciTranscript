import 'dart:async';

import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #25, point 3 : la fusion des repères n'est pas atomique (les
// retraits des repères englobés et l'écriture de l'union passent par des
// chaînes différentes ; une écriture ratée plus tôt pour le même id fait
// sauter l'union). Attendu, avec un dépôt qui échoue une fois :
// - l'union est quand même rangée, aucun intervalle ne reste sans repère ;
// - l'écriture suivante d'un id passe même si la précédente a échoué ;
// - les repères englobés ne sont retirés qu'une fois l'union rangée.
//
// Pertes : A 1:00–1:10, B 1:30–1:40, puis C 1:05–1:35 qui touche les deux :
// union 1:00–1:40.
void main() {
  final RegExp union = RegExp(r'00:01:00\s*[–-]\s*00:01:40');

  List<TranscriptSegmentEntity> markers(InMemoryTranscriptRepository repo) =>
      repo
          .of(AudioSource.output)
          .where(
            (TranscriptSegmentEntity s) =>
                s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )
          .toList();

  void gaps(LiveServiceHarness h, FakeAsync async, {bool third = true}) {
    for (final (int, int) g in <(int, int)>[
      (60000, 70000),
      (90000, 100000),
      if (third) (65000, 95000),
    ]) {
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: h.t0 + g.$1,
          endMs: h.t0 + g.$2,
        ),
      );
      async.elapse(const Duration(milliseconds: 200));
    }
  }

  test('la première écriture du repère échoue : l union est quand même '
      'rangée sous un seul repère', () {
    fakeAsync((FakeAsync async) {
      final _FlakyRepository repo = _FlakyRepository(
        failOnce: (TranscriptSegmentEntity s) => s.text.contains('00:01:10'),
      );
      final LiveServiceHarness h = LiveServiceHarness(async, segments: repo)
        ..start();
      async.elapse(const Duration(seconds: 120));
      gaps(h, async);
      async.elapse(const Duration(seconds: 5));

      expect(repo.failures, 1, reason: 'le dépôt a bien échoué une fois');
      expect(markers(repo), hasLength(1));
      expect(markers(repo).single.text, matches(union));
    });
  });

  test('l écriture de l union échoue une fois : elle est rangée quand même, '
      'aucun intervalle sans repère', () {
    fakeAsync((FakeAsync async) {
      final _FlakyRepository repo = _FlakyRepository(
        failOnce: (TranscriptSegmentEntity s) => union.hasMatch(s.text),
      );
      final LiveServiceHarness h = LiveServiceHarness(async, segments: repo)
        ..start();
      async.elapse(const Duration(seconds: 120));
      gaps(h, async);
      async.elapse(const Duration(seconds: 30));

      expect(repo.failures, 1);
      expect(markers(repo), hasLength(1));
      expect(markers(repo).single.text, matches(union));
    });
  });

  test('les repères englobés restent tant que l union n est pas rangée', () {
    fakeAsync((FakeAsync async) {
      final _FlakyRepository repo = _FlakyRepository(
        hold: (TranscriptSegmentEntity s) => union.hasMatch(s.text),
      );
      final LiveServiceHarness h = LiveServiceHarness(async, segments: repo)
        ..start();
      async.elapse(const Duration(seconds: 120));
      gaps(h, async);
      async.elapse(const Duration(seconds: 5));

      // L'union attend : 1:30–1:40 doit toujours avoir son repère.
      expect(
        markers(
          repo,
        ).where((TranscriptSegmentEntity s) => s.text.contains('00:01:30')),
        hasLength(1),
        reason: 'retiré avant que l union soit rangée',
      );

      repo.release();
      async.elapse(const Duration(seconds: 5));
      expect(markers(repo), hasLength(1));
      expect(markers(repo).single.text, matches(union));
    });
  });
}

/// Dépôt qui échoue une fois sur la première écriture qui vérifie
/// [failOnce], ou retient les écritures qui vérifient [hold].
class _FlakyRepository extends InMemoryTranscriptRepository {
  _FlakyRepository({this.failOnce, this.hold});

  final bool Function(TranscriptSegmentEntity s)? failOnce;
  final bool Function(TranscriptSegmentEntity s)? hold;
  int failures = 0;
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async {
    if (failures == 0 && (failOnce?.call(segment) ?? false)) {
      failures++;
      throw Exception('disque plein');
    }
    if (hold?.call(segment) ?? false) await _gate.future;
    return super.save(segment);
  }
}
