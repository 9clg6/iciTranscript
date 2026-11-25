import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';

import '../../helpers/live_service_fakes.dart';

// Une phrase ou un repère qui ne se range pas (disque plein, erreur
// SQLite « database or disk is full ») n'est jamais perdu en silence.
// Aujourd'hui : `TranscriptionService.saveSegment` rend faux, la phrase
// n'est PAS ajoutée à l'écran et n'est pas réessayée ; un repère est
// réessayé 5 fois (15 s) puis abandonné.
//
// Attendu : réessayé (avec attente croissante, sans limite tant que la note
// ou l'app vit), gardé en mémoire jusqu'à être rangé, l'utilisateur voit
// une erreur (`RecordingStorage.unsavedLines` > 0 sur `storageStream`) ;
// rien de ce qui est montré ne disparaît de l'écran ; une fois la base
// revenue, tout est rangé et l'erreur disparaît.
//
// API supposée : recording_storage_test.dart (`storageStream`,
// `RecordingStorage.unsavedLines`).

/// Base qui refuse d'écrire tant que [full] est vrai.
final class _FullDisk extends InMemoryTranscriptRepository {
  bool full = false;

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) {
    if (full) {
      throw Exception('SqliteException(13): database or disk is full');
    }
    return super.save(segment);
  }
}

void main() {
  late _FullDisk repo;
  late LiveServiceHarness h;
  late List<RecordingStorage> storage;

  void setUpIn(FakeAsync async) {
    repo = _FullDisk();
    h = LiveServiceHarness(async, segments: repo)..start();
    storage = <RecordingStorage>[];
    h.service.storageStream.listen(storage.add);
  }

  List<String> onScreen() => h.transcription.segmentsStream.value
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  void say(int atMs, String text) => h.fakeRemote.emitDone(
    AudioSource.input,
    text,
    window: UtteranceWindow(
      startMs: h.t0 + atMs,
      endMs: h.t0 + atMs + 3000,
      hadSpeech: true,
    ),
  );

  test('phrase non rangée : montrée quand même, erreur visible, rangée dès '
      'que la base revient', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      async.elapse(const Duration(seconds: 5));
      repo.full = true;
      say(5000, 'Phrase pendant le disque plein.');
      async.elapse(const Duration(seconds: 2));

      expect(onScreen(), contains('Phrase pendant le disque plein.'));
      expect(storage.last.unsavedLines, greaterThan(0));

      async.elapse(const Duration(minutes: 3));
      expect(
        onScreen(),
        contains('Phrase pendant le disque plein.'),
        reason: 'jamais retirée de l écran',
      );
      repo.full = false;
      async.elapse(const Duration(minutes: 2));
      expect(
        repo.store.values.map((TranscriptSegmentEntity s) => s.text),
        contains('Phrase pendant le disque plein.'),
      );
      expect(storage.last.unsavedLines, 0);
    });
  });

  test('repère de perte non rangé pendant 2 min : gardé, montré, rangé au '
      'retour de la base (pas d abandon après 15 s)', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      async.elapse(const Duration(seconds: 5));
      repo.full = true;
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: h.t0 + 2000,
          endMs: h.t0 + 9000,
        ),
      );
      async.elapse(const Duration(minutes: 2));
      expect(storage.last.unsavedLines, greaterThan(0));
      expect(
        onScreen().where(
          (String t) => t.startsWith(LiveTranscriptionService.gapMarkerPrefix),
        ),
        isNotEmpty,
        reason: 'le repère est montré même non rangé',
      );
      repo.full = false;
      async.elapse(const Duration(minutes: 2));
      expect(
        repo.store.values.where(
          (TranscriptSegmentEntity s) =>
              s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
        ),
        hasLength(1),
      );
      expect(storage.last.unsavedLines, 0);
    });
  });

  test('arrêt pendant que la base refuse : rien n est jeté, tout est rangé '
      'quand elle revient', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      async.elapse(const Duration(seconds: 5));
      repo.full = true;
      say(5000, 'Dernière phrase avant l arrêt.');
      async.elapse(const Duration(seconds: 2));
      h.stop();
      async.elapse(const Duration(minutes: 1));
      repo.full = false;
      async.elapse(const Duration(minutes: 3));
      expect(
        repo.store.values.map((TranscriptSegmentEntity s) => s.text),
        contains('Dernière phrase avant l arrêt.'),
      );
    });
  });

  test('garde : base saine, aucune erreur', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      say(5000, 'Tout va bien.');
      async.elapse(const Duration(seconds: 2));
      expect(onScreen(), contains('Tout va bien.'));
      expect(storage.isEmpty || storage.last.unsavedLines == 0, isTrue);
    });
  });
}
