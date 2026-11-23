import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';

import '../../../helpers/dictation_fakes.dart';

/// Dictée avec un raccourci « modificateurs seuls » (⌘⌥, sans autre touche),
/// demandé par l'utilisateur (« un raccourci à deux touches »).
///
/// Comportement épinglé :
/// - le raccourci est posé par `registerModifiers` (masque Carbon), jamais
///   par `register` (Carbon ne sait pas poser un raccourci sans touche) ;
/// - mêmes gestes qu'un raccourci à touche : appui bref (< 300 ms) =
///   bascule, appui maintenu = parler tant qu'il est tenu ;
/// - `aborted` (le plugin a vu une autre touche pendant que ⌘⌥ étaient
///   tenus : l'utilisateur tape ⌘⌥Échap ou ⌘⌥D d'une autre app) :
///   - la dictée lancée par cet appui est jetée sans bruit : rien collé,
///     rien copié, ni erreur ni « rien entendu », capture arrêtée, flux
///     fermé, Échap libérée, serveur rendu à l'arbitre ;
///   - une dictée déjà en cours (lancée par un appui bref plus tôt) n'est
///     PAS arrêtée par cet appui : elle continue, un appui bref suivant
///     l'arrête comme d'habitude ;
///   - un `released` égaré après `aborted` ne fait rien ;
/// - Échap (`cancel`) annule toujours une dictée en cours ;
/// - Accessibilité absente : le plugin refuse, l'état du raccourci dit
///   `ShortcutStatus.needsAccessibility` (jamais « déjà pris », jamais
///   « posé ») ; réappliquer les réglages après l'accord repose le raccourci.
///
/// Contrat du canal : global_shortcut_modifier_only_test.dart.
void main() {
  const DictationShortcut cmdOption = DictationShortcut(
    keyCode: null,
    modifiers: 256 | 2048,
  );
  const DictationSettings clipboardMode = DictationSettings(
    shortcut: cmdOption,
    outputMode: DictationOutputMode.clipboard,
  );
  const DictationSettings pasteMode = DictationSettings(
    shortcut: cmdOption,
    outputMode: DictationOutputMode.paste,
  );

  DictationHarness launched(
    FakeAsync async, {
    DictationSettings settings = clipboardMode,
  }) => DictationHarness(async)..launch(settings);

  void abort(DictationHarness d) {
    d.shortcuts.emit(ShortcutEvent.aborted);
    d.async.elapse(Duration.zero);
  }

  /// États montrés à partir de maintenant.
  List<DictationState> watch(DictationHarness d) {
    final List<DictationState> seen = <DictationState>[];
    d.controller.stateStream.skip(1).listen(seen.add);
    d.async.elapse(Duration.zero);
    return seen;
  }

  /// Rien ne reste de la dictée jetée : ni texte, ni capture, ni flux, ni
  /// Échap, ni prise du serveur, ni état d'échec.
  void expectDiscarded(DictationHarness d, List<DictationState> seen) {
    d.async.elapse(DictationController.finalTextTimeout * 2);
    expect(d.state, isA<DictationIdle>());
    expect(d.output.log, isEmpty, reason: 'rien collé ni copié');
    expect(d.remote.finalCommits, 0, reason: 'rien envoyé à transcrire');
    expect(d.audio.stopCalls, 1, reason: 'capture arrêtée');
    expect(d.remote.connected, isFalse, reason: 'flux fermé');
    expect(d.shortcuts.cancelKey.last, isFalse, reason: 'Échap libérée');
    expect(d.arbiter.backfillMustYield, isFalse, reason: 'serveur rendu');
    expect(
      seen.where(
        (DictationState s) =>
            s is DictationDone ||
            s is DictationNothingHeard ||
            s is DictationError,
      ),
      isEmpty,
      reason: 'jeté sans bruit',
    );
  }

  group('enregistrement du raccourci', () {
    test('⌘⌥ seuls : posé par registerModifiers, jamais comme une touche', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        expect(d.shortcuts.registeredModifiers, <int>[2304]);
        expect(d.shortcuts.registered, isEmpty);
        expect(d.controller.shortcutStatus, ShortcutStatus.registered);
      });
    });

    test('de ⌃⌥Espace à ⌘⌥ puis retour : l ancien retiré chaque fois', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(
          async,
          settings: const DictationSettings(),
        );
        expect(d.shortcuts.registered, hasLength(1));

        unawaited(d.controller.apply(clipboardMode));
        async.elapse(Duration.zero);
        expect(d.shortcuts.unregisterCalls, 1);
        expect(d.shortcuts.registeredModifiers, <int>[2304]);

        unawaited(d.controller.apply(const DictationSettings()));
        async.elapse(Duration.zero);
        expect(d.shortcuts.unregisterCalls, 2);
        expect(d.shortcuts.registered.last, (keyCode: 49, modifiers: 6144));
        expect(d.shortcuts.registeredModifiers, <int>[2304]);
      });
    });
  });

  group('mêmes gestes qu un raccourci à touche', () {
    test('appui bref : la dictée continue ; un second appui bref l arrête et '
        'produit le texte une fois', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        async.elapse(const Duration(milliseconds: 120));
        d.release();
        d.say(20);
        expect(d.state, isA<DictationListening>());
        expect(d.remote.finalCommits, 0);

        d.press();
        d.release();
        expect(d.state, isA<DictationTranscribing>());
        d.remote.emitDone('Bonjour à tous.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['Bonjour à tous.']);
      });
    });

    test('appui maintenu : parler tant que ⌘⌥ sont tenus, le relâchement '
        'arrête', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        d.say(8);
        expect(d.state, isA<DictationListening>());
        d.release();

        expect(d.state, isA<DictationTranscribing>());
        d.remote.emitDone('Note rapide.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Note rapide.']);
      });
    });

    test('Échap annule une dictée en cours, comme avant', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.release();
        d.say(5);

        d.cancel();

        expect(d.state, isA<DictationIdle>());
        expect(d.output.log, isEmpty);
      });
    });
  });

  group('une autre touche pendant ⌘⌥ : raccourci d une autre app', () {
    test('pendant les 300 ms : la dictée lancée par cet appui est jetée sans '
        'bruit, rien n est collé', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);
        final List<DictationState> seen = watch(d);

        d.press();
        d.say(1);
        abort(d);

        expectDiscarded(d, seen);
      });
    });

    test('après 2 s tenus à parler : jetée aussi, rien n est collé', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);
        final List<DictationState> seen = watch(d);

        d.press();
        d.say(20);
        abort(d);

        expectDiscarded(d, seen);
      });
    });

    test('un relâchement égaré après l abandon ne fait rien', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        final List<DictationState> seen = watch(d);
        d.press();
        d.say(1);
        abort(d);

        d.release();

        expectDiscarded(d, seen);
        expect(d.audio.startCalls, 1);
      });
    });

    test('une dictée lancée par un appui bref plus tôt n est pas arrêtée ; '
        'un appui bref suivant l arrête', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.release();
        d.say(10);

        // ⌘⌥D tapé dans une autre app pendant la dictée.
        d.press();
        abort(d);
        final int sentBefore = d.remote.sentAudio.length;
        d.say(10);

        expect(d.state, isA<DictationListening>());
        expect(d.audio.stopCalls, 0);
        expect(d.remote.finalCommits, 0);
        expect(d.remote.sentAudio.length, greaterThan(sentBefore));
        expect(d.output.log, isEmpty);

        d.press();
        d.release();
        expect(d.state, isA<DictationTranscribing>());
        d.remote.emitDone('Toujours là.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Toujours là.']);
      });
    });

    test('après un abandon, l appui suivant démarre une dictée normale', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        abort(d);

        d.press();
        d.say(8);
        d.release();
        d.remote.emitDone('Deuxième essai.');
        async.elapse(Duration.zero);

        expect(d.audio.startCalls, 2);
        expect(d.output.copies, <String>['Deuxième essai.']);
      });
    });
  });

  group('Accessibilité', () {
    test('absente : le raccourci n est pas posé et l état le dit (ni « déjà '
        'pris » ni « posé »)', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.output.trusted = false;
        d.shortcuts.registerModifiersResult = false;

        d.launch(clipboardMode);

        expect(d.shortcuts.registeredModifiers, <int>[2304]);
        expect(
          d.controller.shortcutStatus,
          ShortcutStatus.needsAccessibility,
        );
      });
    });

    test('accordée ensuite : réappliquer les mêmes réglages repose le '
        'raccourci, qui marche', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.output.trusted = false;
        d.shortcuts.registerModifiersResult = false;
        d.launch(clipboardMode);

        d.output.trusted = true;
        d.shortcuts.registerModifiersResult = true;
        unawaited(d.controller.apply(clipboardMode));
        async.elapse(Duration.zero);

        expect(d.shortcuts.registeredModifiers, <int>[2304, 2304]);
        expect(d.controller.shortcutStatus, ShortcutStatus.registered);
        d.press();
        expect(d.state, isA<DictationListening>());
      });
    });
  });
}
