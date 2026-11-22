import 'dart:convert';

import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Dictée (T2) : au relâchement du raccourci, seule la phrase du micro est
/// finalisée ; celle de l'audio système continue, intacte.
///
/// API supposée sur `TranscriptionRemoteDataSource` :
/// `Set<AudioSource> sendCommit({bool isFinal = false, Set<AudioSource>? sources})`
/// — `sources` null : toutes (comme avant) ; sinon seules les sources
/// listées. Rend les sources dont une phrase ouverte a été finalisée (un
/// `done` viendra).
void main() {
  int finalCommits(List<String> received) => received
      .map((String m) => jsonDecode(m) as Map<String, dynamic>)
      .where(
        (Map<String, dynamic> m) =>
            m['type'] == 'input_audio_buffer.commit' && m['final'] == true,
      )
      .length;

  const Map<AudioSource, bool> bothSpeaking = <AudioSource, bool>{
    AudioSource.input: true,
    AudioSource.output: true,
  };

  test('commit du micro seul : le système n est pas finalisé', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      for (int id = 0; id < 20; id++) {
        b.tick(id, voiced: bothSpeaking);
      }

      final Set<AudioSource> finalized = b.dataSource.sendCommit(
        isFinal: true,
        sources: <AudioSource>{AudioSource.input},
      );

      expect(finalized, <AudioSource>{AudioSource.input});
      expect(finalCommits(b.mic.received), 1);
      expect(finalCommits(b.system.received), 0);
      expect(b.dataSource.activeSources, contains(AudioSource.output));
    });
  });

  test(
    'la phrase système continue et se termine d elle-même, une seule fois',
    () {
      fakeAsync((FakeAsync async) {
        final DataSourceBench b = DataSourceBench(async);
        for (int id = 0; id < 20; id++) {
          b.tick(id, voiced: bothSpeaking);
        }
        b.dataSource.sendCommit(
          isFinal: true,
          sources: <AudioSource>{AudioSource.input},
        );
        for (int id = 20; id < 40; id++) {
          b.tick(
            id,
            voiced: const <AudioSource, bool>{AudioSource.output: true},
          );
        }
        for (int id = 40; id < 60; id++) {
          b.tick(
            id,
            voiced: const <AudioSource, bool>{AudioSource.output: false},
          );
        }

        expect(finalCommits(b.system.received), 1);
      });
    },
  );

  test(
    'micro sans phrase ouverte : rien n est finalisé, rien n est envoyé',
    () {
      fakeAsync((FakeAsync async) {
        final DataSourceBench b = DataSourceBench(async);
        for (int id = 0; id < 20; id++) {
          b.tick(
            id,
            voiced: const <AudioSource, bool>{AudioSource.output: true},
          );
        }

        final Set<AudioSource> finalized = b.dataSource.sendCommit(
          isFinal: true,
          sources: <AudioSource>{AudioSource.input},
        );

        expect(finalized, isEmpty);
        expect(finalCommits(b.system.received), 0);
      });
    },
  );

  test('sans sources : les deux sont finalisées, comme avant', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      for (int id = 0; id < 20; id++) {
        b.tick(id, voiced: bothSpeaking);
      }

      expect(b.dataSource.sendCommit(isFinal: true), <AudioSource>{
        AudioSource.input,
        AudioSource.output,
      });
    });
  });
}
