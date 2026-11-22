import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';

/// Tour 5, point 1 (sonde 2, scénarios D et E) : pendant un rattrapage
/// étalé, le serveur ferme la socket micro. Aucun envoi micro n'est dû (le
/// client attend un `done`), la socket système reçoit des messages. Le
/// client doit voir la fermeture lui-même (fin ou erreur du canal), pas au
/// prochain envoi : coupure en moins de 2 s, reconnexion, renvoi étalé,
/// rien de perdu.
///
/// API supposée du client : `Stream<void> onClosed` (le faux l'émet). Une
/// surveillance de `isConnected` passerait aussi.
void main() {
  test('une socket fermée par le serveur pendant le rattrapage est vue en '
      'moins de 2 s, rouverte, et rien n est perdu', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = DataSourceBench(async);
      b.mic
        ..drop()
        ..accepting = false;
      final List<int> voiced = b.speak(AudioSource.input, 0, 6); // arriéré
      b.mic.accepting = true;
      async.elapse(const Duration(seconds: 12)); // reconnecté, 30 s en vol
      expect(b.mic.connections, hasLength(2), reason: 'reconnecté');

      final int attemptsBefore = b.mic.connectAttempts.length;
      final Duration closedAt = async.elapsed;
      b.mic
        ..autoDoneAfter = const Duration(seconds: 1)
        ..drop(); // fermeture côté serveur, notifiée
      for (int s = 0; s < 4; s++) {
        b.systemChatter();
        async.elapse(const Duration(milliseconds: 500));
      }

      expect(
        b.mic.connectAttempts.length,
        greaterThan(attemptsBefore),
        reason: 'fermeture vue sans attendre un envoi',
      );
      expect(
        b.mic.connectAttempts[attemptsBefore] - closedAt,
        lessThanOrEqualTo(const Duration(seconds: 2)),
      );

      async.elapse(const Duration(minutes: 2));
      expect(b.gaps, isEmpty);
      expect(b.mic.transcribedTwice, isEmpty);
      expect(
        voiced.where((int id) => !b.mic.transcribedIds.contains(id)),
        isEmpty,
        reason: 'chaque chunk voisé transcrit',
      );
      expect(b.mic.maxInFlightChunks, lessThanOrEqualTo(320));
    });
  });
}
