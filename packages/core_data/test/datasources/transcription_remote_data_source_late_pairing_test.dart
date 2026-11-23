import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Revue PR #21, appariement (points c et d) : sur une connexion, les
/// `done` arrivent dans l'ordre des commits ; un `done` est apparié à la
/// plus ancienne phrase attendue. Constat à la lecture du code : toute
/// perte qui abandonne des phrases attendues (coupure, serveur muet après
/// ses reprises, arrêt) remplace aussi la connexion ; un texte tardif de la
/// perte ne peut donc pas arriver sur la même connexion qu'une phrase plus
/// récente (c n'est pas atteignable aujourd'hui), et rien de l'ancienne
/// connexion ne peut plus arriver (d).
void main() {
  const int t0 = DataSourceBench.t0;

  List<TranscriptEventRemoteModel> doneOf(List<TranscriptEventRemoteModel> e) =>
      e
          .where(
            (TranscriptEventRemoteModel x) =>
                x.type == 'response.audio_transcript.done',
          )
          .toList();

  /// Phrase micro de 1 s puis pause (commit final), à partir de [from].
  void sentence(DataSourceBench b, int from) {
    for (int id = from; id < from + 25; id++) {
      b.tick(
        id,
        voiced: <AudioSource, bool>{AudioSource.input: id < from + 10},
      );
    }
  }

  test('c. deux phrases attendues sur une connexion : chaque done reçoit la '
      'fenêtre de sa phrase, dans l ordre des commits', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      sentence(b, 0); // A
      sentence(b, 100); // B, A toujours sans réponse
      for (final String t in <String>['phrase A', 'phrase B']) {
        b.mic.emit(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': t,
        });
      }
      async.flushMicrotasks();

      final List<TranscriptEventRemoteModel> done = doneOf(b.micEvents);
      expect(done.map((TranscriptEventRemoteModel e) => e.text), <String>[
        'phrase A',
        'phrase B',
      ]);
      expect(b.dataSource.windowOf(done[0])?.startMs, t0);
      expect(b.dataSource.windowOf(done[1])?.startMs, t0 + 100 * 100);
    });
  });

  test(
    'd. serveur muet abandonné : la connexion est remplacée, rien de '
    'l ancienne n arrive, et la phrase suivante reçoit sa propre fenêtre',
    () {
      fakeAsync((FakeAsync async) {
        final DataSourceBench b = DataSourceBench(async);
        sentence(b, 0); // A, jamais de réponse
        final int abandonedGeneration = b.mic.generation;
        async.elapse(const Duration(minutes: 10)); // reprises, puis abandon
        final List<AudioGap> gaps = b.gaps
            .where((AudioGap g) => g.source == AudioSource.input)
            .toList();
        expect(gaps, isNotEmpty, reason: 'A est signalée perdue');
        expect(b.mic.generation, isNot(abandonedGeneration));

        sentence(b, 7000); // B, sur la nouvelle connexion
        // La réponse tardive à A ne peut venir que de l'ancienne connexion.
        b.mic.emitIfAlive(abandonedGeneration, <String, Object>{
          'type': 'response.audio_transcript.done',
          'text': 'phrase A',
        });
        b.mic.emit(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': 'phrase B',
        });
        async.flushMicrotasks();

        final List<TranscriptEventRemoteModel> done = doneOf(b.micEvents);
        expect(done.map((TranscriptEventRemoteModel e) => e.text), <String>[
          'phrase B',
        ]);
        expect(b.dataSource.windowOf(done.single)?.startMs, t0 + 7000 * 100);
      });
    },
  );
}
