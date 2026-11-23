import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';

import '../../../helpers/dictation_fakes.dart';

/// Aucune dictée n'attend sans fin un événement qui ne vient jamais (revue de
/// la PR #29) : un `released` ou un `aborted` que macOS n'a pas livré (champ
/// de saisie sécurisée qui cache les touches, accord mal vu par le plugin),
/// une bascule oubliée. Vaut pour tous les raccourcis.
///
/// Bornes, en un seul endroit (`DictationController`) :
/// - `noSpeechTimeout` = 8 s : aucune parole depuis le début de la dictée →
///   elle finit sans bruit : capture arrêtée, rien collé ni copié, pas
///   d'erreur, Échap libérée ;
/// - `maxDictationDuration` = 3 min : la capture s'arrête, le texte dit
///   jusque-là est produit une fois ; un relâchement tardif ne fait rien de
///   plus.
///
/// Parole = chunk voisé du faux micro (énergie non nulle).
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );

  DictationHarness launched(FakeAsync async) =>
      DictationHarness(async)..launch(clipboardMode);

  int chunksIn(Duration d) => d.inMilliseconds ~/ 100;

  void expectEndedSilently(DictationHarness d, List<DictationState> seen) {
    expect(d.state, isNot(isA<DictationListening>()));
    expect(d.audio.stopCalls, 1, reason: 'capture arrêtée');
    expect(d.output.log, isEmpty, reason: 'rien collé ni copié');
    expect(d.shortcuts.cancelKey.last, isFalse, reason: 'Échap libérée');
    expect(seen.whereType<DictationError>(), isEmpty, reason: 'sans bruit');
    expect(seen.whereType<DictationDone>(), isEmpty);
  }

  List<DictationState> watch(DictationHarness d) {
    final List<DictationState> seen = <DictationState>[];
    d.controller.stateStream.listen(seen.add);
    d.async.elapse(Duration.zero);
    return seen;
  }

  test('bornes : 8 s sans parole, 3 min au plus', () {
    expect(DictationController.noSpeechTimeout, const Duration(seconds: 8));
    expect(
      DictationController.maxDictationDuration,
      const Duration(minutes: 3),
    );
  });

  group('aucune parole', () {
    test('bascule sans un mot : finit sans bruit à 8 s, pas avant', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        final List<DictationState> seen = watch(d);
        d.press();
        d.release(); // appui bref : bascule, plus aucun événement attendu

        d.say(chunksIn(DictationController.noSpeechTimeout) - 2, voiced: false);
        expect(d.state, isA<DictationListening>());
        d.say(3, voiced: false);
        async.elapse(DictationController.finalTextTimeout);

        expectEndedSilently(d, seen);
      });
    });

    test('appui maintenu dont le relâchement n arrive jamais : finit sans '
        'bruit à 8 s', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        final List<DictationState> seen = watch(d);
        d.press();

        d.say(chunksIn(DictationController.noSpeechTimeout) + 1, voiced: false);
        async.elapse(DictationController.finalTextTimeout);

        expectEndedSilently(d, seen);
      });
    });

    test('quelques mots au début : pas de fin à 8 s du début', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.release();

        d.say(10);
        d.say(chunksIn(DictationController.noSpeechTimeout) - 10, voiced: false);
        d.say(2, voiced: false);

        expect(d.state, isA<DictationListening>());
        expect(d.audio.stopCalls, 0);
      });
    });
  });

  group('durée maximale', () {
    test('bascule qui parle sans fin : arrêt à 3 min, le texte est produit '
        'une fois', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.release();

        d.say(chunksIn(DictationController.maxDictationDuration) - 2);
        expect(d.state, isA<DictationListening>());
        expect(d.remote.finalCommits, 0);
        d.say(3);

        expect(d.state, isA<DictationTranscribing>());
        expect(d.remote.finalCommits, 1);
        d.remote.emitDone('Long discours.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Long discours.']);
      });
    });

    test('appui maintenu sans relâchement : arrêt à 3 min, texte produit ; '
        'le relâchement tardif ne fait rien de plus', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();

        d.say(chunksIn(DictationController.maxDictationDuration) + 1);
        expect(d.state, isA<DictationTranscribing>());
        d.remote.emitDone('Texte jusque-là.');
        async.elapse(Duration.zero);
        d.release();
        async.elapse(const Duration(seconds: 1));

        expect(d.output.copies, <String>['Texte jusque-là.']);
        expect(d.remote.finalCommits, 1);
        expect(d.audio.startCalls, 1);
      });
    });
  });
}
