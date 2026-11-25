import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart' as wall;
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Dictée avec un raccourci « modificateurs seuls » (⌘⌥, sans autre touche),
/// demandé par l'utilisateur (« un raccourci à deux touches »).
///
/// Comportement épinglé :
/// - le raccourci est posé par `registerModifiers` (masque Carbon), jamais
///   par `register` (Carbon ne sait pas poser un raccourci sans touche) ;
/// - un accord n'agit qu'une fois su être le nôtre (revue PR #29) : le
///   plugin ne dit rien pendant le seuil d'appui, que le contrôleur lui
///   transmet (`DictationController.holdThreshold`, seule source) ; ⌘⌥ puis
///   une touche ou un clic pendant ce seuil ne produit AUCUN événement, donc
///   rien ici (ni capture, ni micro de réunion détourné, ni collage) ;
/// - `tapped` (appui bref propre) = bascule : il démarre, le suivant arrête ;
/// - `pressed` arrive au seuil : appui maintenu déjà confirmé, capture
///   ouverte à ce moment ; `released` arrête quelle que soit l'attente entre
///   les deux (le seuil n'est jamais recompté côté Dart) ;
/// - `aborted` (autre touche ou clic après `pressed` : l'utilisateur tenait
///   ⌘⌥ puis a tapé ⌘⌥Échap ou ⌘⌥D d'une autre app) :
///   - la dictée lancée par cet appui est jetée sans bruit : rien collé,
///     rien copié, ni erreur ni « rien entendu », capture arrêtée, flux
///     fermé, Échap libérée, serveur rendu à l'arbitre ;
///   - une dictée déjà en cours (lancée par un appui bref plus tôt) n'est
///     PAS arrêtée par cet appui : elle continue, un appui bref suivant
///     l'arrête comme d'habitude ;
///   - un `released` égaré après `aborted` ne fait rien ;
/// - pendant un enregistrement (dictée prise sur le micro de la réunion) :
///   même règle, l'enregistrement continue ; ce que devient la phrase de
///   réunion dite pendant un appui abandonné (note ou exclue comme une
///   dictée annulée) n'est pas tranché ici ;
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

  /// Appui bref propre, confirmé par le plugin.
  void tap(DictationHarness d) {
    d.shortcuts.emit(ShortcutEvent.tapped);
    d.async.elapse(Duration.zero);
  }

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
        expect(
          d.shortcuts.registeredHoldThresholds.last,
          DictationController.holdThreshold,
          reason: 'le seuil vient du contrôleur, nulle part ailleurs',
        );
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
    test('tant que le plugin ne dit rien, rien ne s ouvre (accord indécis '
        'ou raccourci d une autre app)', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        final int startsBefore = d.process.starts.length;

        async.elapse(const Duration(seconds: 2));

        expect(d.audio.startCalls, 0);
        expect(d.remote.connects, isEmpty);
        expect(d.process.starts.length, startsBefore);
        expect(d.output.log, isEmpty);
      });
    });

    test('appui bref (tapped) : la dictée démarre et continue ; un second '
        'appui bref l arrête et produit le texte une fois', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        tap(d);
        expect(d.state, isA<DictationListening>());
        d.say(20);
        expect(d.remote.finalCommits, 0);

        tap(d);
        expect(d.state, isA<DictationTranscribing>());
        d.remote.emitDone('Bonjour à tous.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['Bonjour à tous.']);
      });
    });

    test('pressed puis released 50 ms après : arrêt (le maintien est déjà '
        'confirmé par le plugin, jamais pris pour une bascule)', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        async.elapse(const Duration(milliseconds: 50));
        d.release();

        expect(d.state, isNot(isA<DictationListening>()));
        expect(d.audio.stopCalls, 1);
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
        tap(d);
        d.say(5);

        d.cancel();

        expect(d.state, isA<DictationIdle>());
        expect(d.output.log, isEmpty);
      });
    });
  });

  group('une autre touche pendant ⌘⌥ : raccourci d une autre app', () {
    test('juste après le seuil : la dictée lancée par cet appui est jetée sans '
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
        tap(d);
        d.say(10);

        // ⌘⌥ tenus au-delà du seuil puis D (raccourci d'une autre app).
        d.press();
        abort(d);
        final int sentBefore = d.remote.sentAudio.length;
        d.say(10);

        expect(d.state, isA<DictationListening>());
        expect(d.audio.stopCalls, 0);
        expect(d.remote.finalCommits, 0);
        expect(d.remote.sentAudio.length, greaterThan(sentBefore));
        expect(d.output.log, isEmpty);

        tap(d);
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

        expect(d.shortcuts.registered, isEmpty);
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

        expect(d.shortcuts.registeredModifiers.last, 2304);
        expect(d.controller.shortcutStatus, ShortcutStatus.registered);
        d.press();
        expect(d.state, isA<DictationListening>());
      });
    });
  });

  group('pendant un enregistrement', () {
    late LiveServiceHarness h;
    late DictationHarness d;
    late FakeAsync clock;
    int id = 0;

    setUp(() {
      final Directory dir = Directory(LiveTranscriptionService.recordingsDir);
      expect(dir.path, startsWith(Directory.systemTemp.path));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    void setUpIn(FakeAsync async) {
      clock = async;
      id = 0;
      final FakeVoxServer server = FakeVoxServer();
      final FakeVoxSocket mic = FakeVoxSocket(server)
        ..reply = (int n) => 'Phrase $n.';
      h = LiveServiceHarness(
        async,
        remote: TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        ),
      );
      d = DictationHarness(async, live: h)..launch(clipboardMode);
      h.start();
    }

    /// [count] × 100 ms de micro, voisé ou non.
    void run(int count, {bool voiced = false}) {
      for (int i = 0; i < count; i++) {
        final int ts = wall.clock.now().millisecondsSinceEpoch;
        h.audio
          ..emit(chunk(AudioSource.input, id, timestampMs: ts, voiced: voiced))
          ..emit(chunk(AudioSource.output, id, timestampMs: ts));
        id++;
        clock.elapse(const Duration(milliseconds: 100));
      }
    }

    void tapIn() {
      d.shortcuts.emit(ShortcutEvent.tapped);
      clock.elapse(Duration.zero);
    }

    void abortIn() {
      d.shortcuts.emit(ShortcutEvent.aborted);
      clock.elapse(Duration.zero);
    }

    test('appui abandonné : aucun texte, l enregistrement continue', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        run(20, voiced: true);
        run(15);

        d.press();
        run(3, voiced: true);
        abortIn();
        run(20, voiced: true);
        run(20);
        async.elapse(const Duration(seconds: 2));

        expect(d.output.log, isEmpty);
        expect(d.state, isA<DictationIdle>());
        expect(h.service.isRecording, isTrue);
        expect(h.audio.stopCalls, 0);
      });
    });

    test('dictée en bascule : un appui abandonné ne l arrête pas, un appui '
        'bref suivant l arrête', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        run(20, voiced: true);
        run(15);

        tapIn();
        run(10, voiced: true);
        d.press();
        abortIn();
        run(10, voiced: true);
        expect(d.state, isA<DictationListening>());
        expect(d.output.log, isEmpty);

        tapIn();
        run(20);
        async.elapse(const Duration(seconds: 2));

        expect(d.state, isA<DictationDone>());
        expect(d.output.copies, hasLength(1));
        expect(h.service.isRecording, isTrue);
      });
    });
  });
}
