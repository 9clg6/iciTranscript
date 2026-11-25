import 'dart:async';

import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';

import '../../helpers/live_service_fakes.dart';

// Revue de la PR #31, point 2 : réessayer sans limite ne doit pas bloquer
// l'arrêt.
//
// Attendu :
// - base qui ne revient jamais : l'arrêt rend la main dans sa borne — rien
//   n'étant en vol ici, en moins de 15 s (la borne générale reste l'attente
//   de l'arrêt, 120 s) — et une nouvelle note démarre ; les lignes non
//   rangées restent montrées après l'arrêt et comptées
//   (`RecordingStorage.unsavedLines`) après le départ de la note suivante ;
// - une erreur qui n'est PAS un disque plein (contrainte SQLite, base
//   fermée) ne boucle pas : attente croissante 1, 2, 4, 8, 16, puis 30 s
//   entre deux essais d'une même ligne (jamais moins d'1 s).
const Duration _stopBound = Duration(seconds: 15);
const List<Duration> _delays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
  Duration(seconds: 30),
];

/// Base qui refuse toujours d'écrire [refused] avec [error], et note
/// l'heure de chaque essai.
final class _Refusing extends InMemoryTranscriptRepository {
  _Refusing(this.async, this.error);

  final FakeAsync async;
  final Object error;
  bool refusing = true;
  final Map<String, List<Duration>> attempts = <String, List<Duration>>{};

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) {
    (attempts[segment.text] ??= <Duration>[]).add(async.elapsed);
    if (refusing) throw error;
    return super.save(segment);
  }
}

void main() {
  void say(LiveServiceHarness h, int atMs, String text) =>
      h.fakeRemote.emitDone(
        AudioSource.input,
        text,
        window: UtteranceWindow(
          startMs: h.t0 + atMs,
          endMs: h.t0 + atMs + 3000,
          hadSpeech: true,
        ),
      );

  test('base qui ne revient jamais : l arrêt rend la main, une nouvelle note '
      'démarre, les lignes non rangées restent montrées et comptées', () {
    fakeAsync((FakeAsync async) {
      final _Refusing db = _Refusing(
        async,
        Exception('SqliteException(13): database or disk is full'),
      );
      final LiveServiceHarness h = LiveServiceHarness(async, segments: db)
        ..start();
      final List<RecordingStorage> storage = <RecordingStorage>[];
      h.service.storageStream.listen(storage.add);
      async.elapse(const Duration(seconds: 5));
      say(h, 5000, 'Jamais rangée.');
      async.elapse(const Duration(seconds: 2));
      final String first = h.session.id;

      bool stopped = false;
      final Duration stopAt = async.elapsed;
      unawaited(h.service.stopTranscription().then((_) => stopped = true));
      while (!stopped && async.elapsed - stopAt < const Duration(minutes: 5)) {
        async.elapse(const Duration(seconds: 1));
      }
      expect(stopped, isTrue, reason: 'l arrêt a rendu la main');
      expect(
        async.elapsed - stopAt,
        lessThanOrEqualTo(_stopBound),
        reason: 'arrêt en ${async.elapsed - stopAt}',
      );
      expect(
        h.transcription.segmentsStream.value.map(
          (TranscriptSegmentEntity s) => s.text,
        ),
        contains('Jamais rangée.'),
        reason: 'toujours montrée après l arrêt',
      );
      expect(storage.last.unsavedLines, greaterThan(0));

      h.start();
      expect(h.service.isRunning, isTrue, reason: 'nouvelle note');
      expect(h.session.id, isNot(first));
      async.elapse(const Duration(minutes: 1));
      expect(storage.last.unsavedLines, greaterThan(0), reason: 'comptée');
    });
  });

  for (final (String name, Object error) in <(String, Object)>[
    (
      'contrainte SQLite',
      Exception('SqliteException(19): UNIQUE constraint failed'),
    ),
    ('base fermée', StateError('database is closed')),
  ]) {
    test('$name : pas de boucle serrée, attentes 1, 2, 4, 8, 16, 30, 30 s', () {
      fakeAsync((FakeAsync async) {
        final _Refusing db = _Refusing(async, error);
        final LiveServiceHarness h = LiveServiceHarness(async, segments: db)
          ..start();
        async.elapse(const Duration(seconds: 5));
        say(h, 5000, 'Refusée par la base.');
        async.elapse(const Duration(minutes: 10));

        final List<Duration> at = db.attempts['Refusée par la base.']!;
        expect(at.length, lessThanOrEqualTo(30), reason: '${at.length} essais');
        final List<Duration> waits = <Duration>[
          for (int i = 1; i < at.length; i++) at[i] - at[i - 1],
        ];
        for (final Duration w in waits) {
          expect(w, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
        }
        for (int i = 0; i < _delays.length && i < waits.length; i++) {
          expect(
            (waits[i] - _delays[i]).inMilliseconds.abs(),
            lessThanOrEqualTo(300),
            reason: 'attente ${i + 1} : ${waits[i]} au lieu de ${_delays[i]}',
          );
        }
        expect(waits.length, greaterThanOrEqualTo(_delays.length));
      });
    });
  }
}
