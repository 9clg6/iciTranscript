import 'dart:async';

import 'package:core_data/model/audio_chunk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Dictée (T2), hors réunion : raccourci global (maintien = parler tant que
/// la touche est tenue ; appui bref = bascule), un flux de transcription à
/// elle (micro seul), texte final nettoyé puis produit une seule fois
/// (presse-papiers ou collage dans l'app au premier plan).
///
/// Choix tranchés ici :
/// - un appui pendant la transcription est ignoré (son relâchement aussi) ;
/// - serveur pas prêt : la capture commence tout de suite, l'audio est gardé
///   jusqu'à [DictationController.maxStartingBuffer] ; à cette borne la
///   capture s'arrête (comme un relâchement) et tout est transcrit une fois
///   le serveur prêt : rien n'est jeté ;
/// - texte final arrivé après le délai de garde : posé sur le presse-papiers,
///   jamais collé (le champ actif a pu changer).
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );
  const DictationSettings pasteMode = DictationSettings(
    outputMode: DictationOutputMode.paste,
  );

  DictationHarness launched(
    FakeAsync async, {
    DictationSettings settings = clipboardMode,
  }) => DictationHarness(async)..launch(settings);

  /// Dictée complète : maintien 1 s, puis le serveur rend [text].
  void dictate(DictationHarness d, String text) {
    d.holdAndSay(10);
    d.remote.emitDone(text);
    d.async.elapse(Duration.zero);
  }

  group('raccourci : maintien et appui bref', () {
    test('appui maintenu 300 ms : écoute tant que la touche est tenue, le '
        'relâchement arrête', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        expect(d.state, isA<DictationListening>());
        d.say(3);
        d.release();

        expect(d.state, isA<DictationTranscribing>());
        expect(d.remote.finalCommits, 1);
        expect(d.audio.stopCalls, 1);
        d.remote.emitDone('Bonjour.');
        async.elapse(Duration.zero);
        expect(d.state, isA<DictationDone>());
        expect((d.state as DictationDone).text, 'Bonjour.');
      });
    });

    test('appui bref (299 ms) : le relâchement ne termine pas, l écoute '
        'continue', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        async.elapse(const Duration(milliseconds: 299));
        d.release();
        d.say(30);

        expect(d.state, isA<DictationListening>());
        expect(d.remote.finalCommits, 0);
        expect(d.audio.stopCalls, 0);
        expect(d.output.log, isEmpty);
      });
    });

    test('appui bref puis nouvel appui : le second appui arrête, son '
        'relâchement ne fait rien de plus', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        d.press();
        d.say(1);
        d.release();
        d.say(20);
        d.press();
        expect(d.state, isA<DictationTranscribing>());
        expect(d.remote.finalCommits, 1);
        d.say(5);
        d.release();
        expect(d.state, isA<DictationTranscribing>());

        d.remote.emitDone('Deux taps.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Deux taps.']);
      });
    });

    test(
      'un appui pendant la transcription est ignoré, son relâchement aussi',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(async);
          d.holdAndSay(10);

          d.press();
          async.elapse(const Duration(seconds: 1));
          d.release();

          expect(d.state, isA<DictationTranscribing>());
          expect(d.audio.startCalls, 1);
          d.remote.emitDone('Un.');
          async.elapse(const Duration(seconds: 2));
          expect(d.state, isA<DictationDone>());
          expect(d.output.copies, <String>['Un.']);
          expect(d.audio.startCalls, 1);
        });
      },
    );

    test('après une dictée finie, un nouvel appui en démarre une autre', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        dictate(d, 'Première.');

        d.press();

        expect(d.state, isA<DictationListening>());
        expect(d.audio.startCalls, 2);
      });
    });

    test(
      'Échap n est capturée que pendant une dictée, libérée à chaque fin',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(async);
          expect(d.shortcuts.cancelKey, isEmpty);

          // Fin normale.
          d.press();
          expect(d.shortcuts.cancelKey, <bool>[true]);
          d.say(5);
          d.release();
          d.remote.emitDone('Texte.');
          async.elapse(Duration.zero);
          expect(d.shortcuts.cancelKey.last, isFalse);

          // Annulation.
          d.press();
          d.cancel();
          expect(d.shortcuts.cancelKey.last, isFalse);

          // Rien entendu.
          d.press();
          d.say(5, voiced: false);
          d.release();
          async.elapse(const Duration(milliseconds: 50));
          expect(d.shortcuts.cancelKey.last, isFalse);

          // Erreur (délai de garde).
          d.holdAndSay(5);
          async.elapse(DictationController.finalTextTimeout * 2);
          expect(d.state, isA<DictationError>());
          expect(d.shortcuts.cancelKey.last, isFalse);

          expect(
            d.shortcuts.cancelKey.where((bool armed) => armed).length,
            d.shortcuts.cancelKey.where((bool armed) => !armed).length,
          );
        });
      },
    );
  });

  group('annulation : rien n est produit', () {
    test('pendant l écoute : retour au repos, capture et flux fermés', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.say(10);

        d.cancel();

        expect(d.state, isA<DictationIdle>());
        expect(d.audio.stopCalls, 1);
        expect(d.remote.connected, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(d.output.log, isEmpty);
      });
    });

    test(
      'pendant la transcription : le texte qui arrive ensuite est ignoré',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(async);
          d.holdAndSay(10);

          d.cancel();
          d.remote.emitDone('Ne pas coller.');
          async.elapse(const Duration(seconds: 5));

          expect(d.state, isA<DictationIdle>());
          expect(d.output.log, isEmpty);
        });
      },
    );

    test(
      'pendant le démarrage du serveur : rien n est envoyé une fois prêt',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = DictationHarness(async);
          d.process.startDuration = const Duration(seconds: 8);
          d.launch(clipboardMode);
          d.press();
          expect(d.state, isA<DictationStarting>());
          d.say(10);

          d.cancel();
          async.elapse(const Duration(seconds: 10));

          expect(d.state, isA<DictationIdle>());
          expect(d.remote.connects, isEmpty);
          expect(d.remote.sentAudio, isEmpty);
          expect(d.output.log, isEmpty);
        });
      },
    );
  });

  group('fin de dictée : texte final nettoyé, produit une seule fois', () {
    test('espaces de bord retirés, espaces internes normalisés', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        dictate(d, '  Bonjour \t à\n  tous  ');

        expect(d.output.copies, <String>['Bonjour à tous']);
        expect((d.state as DictationDone).text, 'Bonjour à tous');
      });
    });

    test('plusieurs phrases dans une dictée : jointes dans l ordre, produites '
        'une seule fois, au relâchement', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.say(10);
        d.remote.pauseDetected();
        d.remote.emitDone('Première phrase.');
        d.say(10);
        expect(d.output.log, isEmpty);
        d.release();
        expect(d.state, isA<DictationTranscribing>());

        d.remote.emitDone('Deuxième phrase.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['Première phrase. Deuxième phrase.']);
      });
    });

    test('filtre de texte final appliqué : boucle de répétition réduite', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        dictate(d, "oui oui oui oui d'accord");

        expect(d.output.copies, <String>["oui d'accord"]);
      });
    });

    test('formule courte dite avec de la parole : gardée', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        dictate(d, 'Thank you.');

        expect(d.output.copies, <String>['Thank you.']);
      });
    });

    test('phrase sans énergie de parole : rien produit, « rien entendu »', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.holdAndSay(10);

        d.remote.emitDone('Bonjour.', hadSpeech: false);
        async.elapse(Duration.zero);

        expect(d.state, isA<DictationNothingHeard>());
        expect(d.output.log, isEmpty);
      });
    });

    test('texte final vide : « rien entendu »', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        dictate(d, '   ');

        expect(d.state, isA<DictationNothingHeard>());
        expect(d.output.log, isEmpty);
      });
    });

    test('seule la phrase avec parole est gardée quand l autre n en a pas', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.say(10);
        d.remote.pauseDetected();
        d.remote.emitDone('Merci.', hadSpeech: false);
        d.say(10);
        d.release();

        d.remote.emitDone('On commence.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['On commence.']);
      });
    });

    test('silence seul : « rien entendu » tout de suite, sans attendre le '
        'délai de garde', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.press();
        d.say(10, voiced: false);

        d.release();
        async.elapse(const Duration(milliseconds: 50));

        expect(d.state, isA<DictationNothingHeard>());
        expect(d.output.log, isEmpty);
        expect(d.audio.stopCalls, 1);
        expect(d.remote.connected, isFalse);
      });
    });

    test('un done en double ne produit pas deux fois le texte', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.holdAndSay(10);

        d.remote
          ..emitDone('Bonjour.')
          ..emitDone('Bonjour.');
        async.elapse(const Duration(seconds: 2));

        expect(d.output.copies, <String>['Bonjour.']);
      });
    });
  });

  group('sortie', () {
    test('mode presse-papiers : le texte est posé sur le presse-papiers', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        dictate(d, 'Bonjour.');

        expect(d.output.log, <String>['copy:Bonjour.']);
        expect(
          (d.state as DictationDone).delivery,
          DictationDelivery.clipboard,
        );
      });
    });

    test('mode collage : presse-papiers sauvé, texte, ⌘V, puis presse-papiers '
        'd avant restauré après le délai de restauration', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);

        dictate(d, 'Bonjour.');

        expect(d.output.log, <String>['save', 'copy:Bonjour.', 'paste']);
        expect((d.state as DictationDone).delivery, DictationDelivery.pasted);
        async.elapse(
          DictationController.pasteRestoreDelay -
              const Duration(milliseconds: 1),
        );
        expect(d.output.log, isNot(contains('restore')));
        async.elapse(const Duration(milliseconds: 2));
        expect(d.output.log, <String>[
          'save',
          'copy:Bonjour.',
          'paste',
          'restore',
        ]);
      });
    });

    test('mode collage sans Accessibilité : repli presse-papiers, signalé', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);
        d.output.trusted = false;

        dictate(d, 'Bonjour.');
        async.elapse(const Duration(seconds: 2));

        expect(d.output.log, <String>['copy:Bonjour.']);
        expect(
          (d.state as DictationDone).delivery,
          DictationDelivery.clipboardNoAccessibility,
        );
      });
    });

    test('collage échoué : le texte reste sur le presse-papiers, rien n est '
        'restauré par-dessus', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);
        d.output.pasteFails = true;

        dictate(d, 'Bonjour.');
        async.elapse(DictationController.pasteRestoreDelay * 3);

        expect(d.output.log, <String>['save', 'copy:Bonjour.', 'paste']);
        expect(d.output.clipboard, 'Bonjour.');
        expect(
          (d.state as DictationDone).delivery,
          DictationDelivery.clipboardPasteFailed,
        );
      });
    });

    test('permission Accessibilité lue au moment de la sortie', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.output.trusted = false;
        d.launch(pasteMode);
        d.press();
        d.say(10);
        d.output.trusted = true;
        d.release();

        d.remote.emitDone('Bonjour.');
        async.elapse(Duration.zero);

        expect((d.state as DictationDone).delivery, DictationDelivery.pasted);
      });
    });

    test('le mode choisi s applique à la dictée suivante', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        dictate(d, 'Un.');
        expect(
          (d.state as DictationDone).delivery,
          DictationDelivery.clipboard,
        );

        unawaited(d.controller.apply(pasteMode));
        async.elapse(const Duration(milliseconds: 10));
        dictate(d, 'Deux.');

        expect((d.state as DictationDone).delivery, DictationDelivery.pasted);
      });
    });
  });

  group('états et délais', () {
    test('états observables dans l ordre : écoute, transcription, fait', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        expect(d.state, isA<DictationIdle>());
        final List<Type> seen = <Type>[];
        d.controller.stateStream.listen(
          (DictationState s) => seen.add(s.runtimeType),
        );

        dictate(d, 'Bonjour.');

        expect(
          seen,
          containsAllInOrder(<Type>[
            DictationListening,
            DictationTranscribing,
            DictationDone,
          ]),
        );
      });
    });

    test('sortie dès l arrivée du texte final, sans délai ajouté', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.holdAndSay(10);
        async.elapse(const Duration(seconds: 3));
        expect(d.state, isA<DictationTranscribing>());
        expect(d.output.log, isEmpty);

        d.remote.emitDone('Tout de suite.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['Tout de suite.']);
      });
    });

    test('délai de garde : erreur explicite au lieu de rester en '
        'transcription', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.holdAndSay(10);

        async.elapse(
          DictationController.finalTextTimeout -
              const Duration(milliseconds: 1),
        );
        expect(d.state, isA<DictationTranscribing>());
        async.elapse(const Duration(milliseconds: 2));

        expect(d.state, isA<DictationError>());
        expect(
          (d.state as DictationError).reason,
          DictationErrorReason.timeout,
        );
        expect(d.output.log, isEmpty);
      });
    });

    test('texte arrivé juste avant le délai de garde : produit', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.holdAndSay(10);
        async.elapse(
          DictationController.finalTextTimeout -
              const Duration(milliseconds: 100),
        );

        d.remote.emitDone('Juste à temps.');
        async.elapse(Duration.zero);

        expect(d.output.copies, <String>['Juste à temps.']);
        expect(d.state, isA<DictationDone>());
      });
    });

    test('texte arrivé après le délai de garde : posé sur le presse-papiers, '
        'jamais collé', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async, settings: pasteMode);
        d.holdAndSay(10);
        async.elapse(
          DictationController.finalTextTimeout + const Duration(seconds: 5),
        );
        expect(d.state, isA<DictationError>());

        d.remote.emitDone('En retard.');
        async.elapse(const Duration(seconds: 1));

        expect(d.output.log, <String>['copy:En retard.']);
        expect(
          (d.state as DictationDone).delivery,
          DictationDelivery.clipboardLate,
        );
      });
    });

    test('micro refusé : erreur explicite, Échap libérée', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.audio.startError = PlatformException(code: 'MIC_PERMISSION_DENIED');

        d.press();
        async.elapse(const Duration(milliseconds: 50));

        expect(d.state, isA<DictationError>());
        expect(
          (d.state as DictationError).reason,
          DictationErrorReason.microphone,
        );
        expect(d.shortcuts.cancelKey.last, isFalse);
      });
    });
  });

  group('serveur pas encore prêt', () {
    test('appui pendant le démarrage : « démarrage » tout de suite, la parole '
        'gardée est transcrite une fois prêt', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(seconds: 8);
        d.launch(clipboardMode);

        d.press();
        expect(d.state, isA<DictationStarting>());
        expect(d.audio.startCalls, 1);
        d.say(20);
        d.release();
        expect(d.remote.connects, isEmpty);
        expect(d.output.log, isEmpty);

        async.elapse(const Duration(seconds: 8));
        expect(d.remote.connects, hasLength(1));
        expect(
          d.remote.sentAudio.map((AudioChunk c) => c.timestampMs).toList(),
          List<int>.generate(20, (int i) => 1000000 + i * 100),
        );
        expect(d.remote.finalCommits, 1);

        d.remote.emitDone('Dit pendant le démarrage.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Dit pendant le démarrage.']);
      });
    });

    test('touche tenue pendant le démarrage : écoute dès que le serveur est '
        'prêt, sans perte', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(seconds: 8);
        d.launch(clipboardMode);

        d.press();
        d.say(90);
        expect(d.state, isA<DictationListening>());
        expect(d.remote.sentAudio, hasLength(90));
        d.release();

        d.remote.emitDone('Long.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Long.']);
      });
    });

    test('à la borne du tampon la capture s arrête et tout ce qui a été '
        'capté est transcrit', () {
      fakeAsync((FakeAsync async) {
        expect(
          DictationController.serverStartTimeout,
          greaterThan(
            DictationController.maxStartingBuffer + const Duration(seconds: 5),
          ),
          reason:
              'la borne du tampon doit pouvoir être atteinte avant '
              'l abandon du serveur',
        );
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration =
            DictationController.maxStartingBuffer + const Duration(seconds: 5);
        d.launch(clipboardMode);
        final int bound =
            DictationController.maxStartingBuffer.inMilliseconds ~/ 100;

        d.press();
        int? captured;
        for (int i = 0; i < bound + 20; i++) {
          d.say(1);
          if (captured == null && d.audio.stopCalls > 0) captured = i + 1;
        }
        expect(captured, isNotNull, reason: 'capture arrêtée à la borne');
        expect(captured, inInclusiveRange(bound - 1, bound + 1));
        expect(d.state, isA<DictationTranscribing>());
        d.release();

        async.elapse(const Duration(seconds: 10));
        expect(d.remote.sentAudio, hasLength(captured));
        d.remote.emitDone('Très long.');
        async.elapse(Duration.zero);
        expect(d.output.copies, <String>['Très long.']);
      });
    });

    test('serveur jamais prêt : erreur au plus tard au délai de démarrage', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration =
            DictationController.serverStartTimeout +
            const Duration(seconds: 60);
        d.launch(clipboardMode);
        d.press();
        d.say(10);
        d.release();

        async.elapse(
          DictationController.serverStartTimeout - const Duration(seconds: 2),
        );
        expect(d.state, isNot(isA<DictationError>()));
        async.elapse(const Duration(seconds: 3));

        expect(d.state, isA<DictationError>());
        expect(
          (d.state as DictationError).reason,
          DictationErrorReason.serverUnavailable,
        );
        expect(d.shortcuts.cancelKey.last, isFalse);
      });
    });

    test('serveur en échec : erreur explicite sans attendre', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.process.failStarts = true;
        d.process.crash();

        d.press();
        async.elapse(const Duration(seconds: 1));

        expect(d.state, isA<DictationError>());
        expect(
          (d.state as DictationError).reason,
          DictationErrorReason.serverUnavailable,
        );
      });
    });

    test('serveur tombé depuis le lancement : un appui le relance', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        d.process.crash();
        d.process.startDuration = const Duration(seconds: 3);

        d.press();
        expect(d.state, isA<DictationStarting>());
        expect(d.process.starts, hasLength(2));
        d.say(40);

        expect(d.state, isA<DictationListening>());
      });
    });
  });

  group('serveur chaud et réglages', () {
    test('dictée activée : serveur démarré au lancement, une seule fois, le '
        'même que pour les réunions', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);
        expect(d.process.starts, hasLength(1));
        expect(d.process.starts.single.command, LiveServiceHarness.command);
        expect(d.process.starts.single.args, LiveServiceHarness.args);

        dictate(d, 'Bonjour.');
        d.live.start();
        d.live.stop();

        expect(d.process.starts, hasLength(1));
        expect(d.remote.connects.single.url, DictationHarness.webSocketUrl);
        expect(
          d.remote.connects.single.systemAudioEnabled,
          isFalse,
          reason: 'micro seul : un flux, pas deux',
        );
        expect(d.audio.log.first, 'capture.start(output: false)');
      });
    });

    test(
      'raccourci par défaut ⌥Espace : code 49, modificateurs Carbon 2048',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = DictationHarness(async)
            ..launch(const DictationSettings());

          expect(d.shortcuts.registered, <({int keyCode, int modifiers})>[
            (keyCode: 49, modifiers: 2048),
          ]);
          expect(d.controller.shortcutStatus, ShortcutStatus.registered);
        });
      },
    );

    test(
      'raccourci déjà pris : état d erreur visible, pas d échec silencieux',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = DictationHarness(async);
          d.shortcuts.registerResult = false;
          final List<ShortcutStatus> seen = <ShortcutStatus>[];
          d.controller.shortcutStatusStream.listen(seen.add);

          d.launch(clipboardMode);

          expect(d.controller.shortcutStatus, ShortcutStatus.unavailable);
          expect(seen, contains(ShortcutStatus.unavailable));
        });
      },
    );

    test(
      'changer de raccourci : l ancien est libéré, le nouveau enregistré',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(async);
          const DictationShortcut controlShiftD = DictationShortcut(
            keyCode: 2,
            modifiers: 4096 | 512,
          );

          unawaited(
            d.controller.apply(
              const DictationSettings(
                shortcut: controlShiftD,
                outputMode: DictationOutputMode.clipboard,
              ),
            ),
          );
          async.elapse(const Duration(milliseconds: 10));

          expect(d.shortcuts.unregisterCalls, greaterThanOrEqualTo(1));
          expect(d.shortcuts.registered.last, (keyCode: 2, modifiers: 4608));
          expect(d.controller.shortcutStatus, ShortcutStatus.registered);
        });
      },
    );

    test(
      'dictée désactivée : ni serveur ni raccourci, les appuis sont ignorés',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(
            async,
            settings: const DictationSettings(enabled: false),
          );

          d.press();
          d.say(10);
          d.release();

          expect(d.process.starts, isEmpty);
          expect(d.shortcuts.registered, isEmpty);
          expect(d.controller.shortcutStatus, ShortcutStatus.disabled);
          expect(d.state, isA<DictationIdle>());
          expect(d.audio.startCalls, 0);
        });
      },
    );

    test(
      'activer la dictée ensuite : raccourci enregistré, serveur démarré',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = launched(
            async,
            settings: const DictationSettings(enabled: false),
          );

          unawaited(d.controller.apply(clipboardMode));
          async.elapse(const Duration(milliseconds: 10));

          expect(d.shortcuts.registered, hasLength(1));
          expect(d.process.starts, hasLength(1));
          expect(d.controller.shortcutStatus, ShortcutStatus.registered);
        });
      },
    );

    test('désactiver la dictée libère le raccourci', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = launched(async);

        unawaited(d.controller.apply(const DictationSettings(enabled: false)));
        async.elapse(const Duration(milliseconds: 10));

        expect(d.shortcuts.unregisterCalls, greaterThanOrEqualTo(1));
        expect(d.controller.shortcutStatus, ShortcutStatus.disabled);
      });
    });
  });
}
