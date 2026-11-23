import 'dart:async';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) : envoi de l'instantané et actions du
// panneau, sur le vrai canal `com.icitranscript/status_panel` (contrat :
// en-tête de status_panel_snapshot_test.dart), panneau natif factice.
//
// Faux : direct (PanelLiveViewModel, compte les actions), suggestion du
// shell (PanelSuggestionController, vrais start/dismiss), questions en
// direct (vrai LiveAnswersService, LLM joué par le test). Temps simulé.
//
// API supposée : `statusPanelSyncProvider`
// (lib/features/status_panel/status_panel_sync.provider.dart), gardé en
// vie ; l'écouter démarre l'envoi et la réception des actions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeStatusPanelPlatform panel;
  late PanelLiveViewModel live;
  late PanelSuggestionController suggestion;
  late LiveAnswersHarness answers;
  late ProviderContainer c;

  const String q = 'Est-ce que vous avez prévu une date de livraison ?';

  final LiveTranscriptionState recordingState = LiveTranscriptionState.initial()
      .copyWith(
        isRecording: true,
        duration: const Duration(minutes: 2),
        sessionTitle: 'Revue de sprint',
      );

  /// Monte la synchro dans [async] ; [installPanel] = faux si le plugin
  /// natif manque (vieux macOS, tests).
  void mount(
    FakeAsync async, {
    bool installPanel = true,
    bool localModel = false,
    bool modelReady = true,
  }) {
    panel = FakeStatusPanelPlatform();
    if (installPanel) panel.install();
    live = PanelLiveViewModel();
    suggestion = PanelSuggestionController();
    answers = LiveAnswersHarness(isLocal: localModel, modelReady: modelReady);
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionViewModelProvider.overrideWith(() => live),
        meetingSuggestionControllerProvider.overrideWith(() => suggestion),
        liveAnswersServiceProvider.overrideWithValue(answers.service),
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(const <SessionEntity>[]),
        ),
      ],
    );
    c.listen(statusPanelSyncProvider, (_, _) {});
    async.elapse(const Duration(seconds: 1));
  }

  void dispose(FakeAsync async) {
    c.dispose();
    async.flushMicrotasks();
  }

  void fromPanel(FakeAsync async, String method, [Object? args]) {
    panel.send(method, args);
    async.elapse(const Duration(milliseconds: 500));
  }

  Map<Object?, Object?>? questionOf(Map<Object?, Object?> s) =>
      s['question'] as Map<Object?, Object?>?;

  group('envoi de l\'instantané', () {
    test('au lancement, l\'état courant part tout de suite', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        expect(panel.updates, isNotEmpty);
        expect(panel.last['status'], 'idle');
        dispose(async);
      });
    });

    test('un changement après un moment calme part sans attendre '
        '(moins de 300 ms)', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        async.elapse(const Duration(seconds: 2));

        live.show(recordingState);
        async.elapse(const Duration(milliseconds: 300));

        expect(panel.last['status'], 'recording');
        expect(panel.last['title'], 'Revue de sprint');
        expect(panel.last['elapsedSeconds'], 120);
        dispose(async);
      });
    });

    test('rien ne part quand l\'instantané ne change pas', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(recordingState);
        async.elapse(const Duration(seconds: 1));
        final int before = panel.updates.length;

        // Champs que le panneau ne montre pas.
        live.show(
          recordingState.copyWith(
            micPermission: 'authorized',
            translations: <String, String>{'x': 'y'},
          ),
        );
        async.elapse(const Duration(seconds: 2));

        expect(panel.updates.length, before);
        dispose(async);
      });
    });

    test('pendant le flux d\'une réponse : environ 4 envois par seconde, '
        'pas un par mot, et l\'état final part après la rafale', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(recordingState);
        answers.hear(q);
        async.elapse(const Duration(seconds: 1));
        expect(answers.llm.streams, hasLength(1));
        final int before = panel.updates.length;

        // 2 s de flux, un mot toutes les 50 ms (40 changements).
        for (int i = 0; i < 40; i++) {
          answers.llm.last.delta('mot$i ');
          async.elapse(const Duration(milliseconds: 50));
        }
        final int during = panel.updates.length - before;

        expect(during, inInclusiveRange(4, 10));
        expect(questionOf(panel.last)?['state'], 'answering');

        answers.llm.last.delta('fin.');
        answers.llm.last.end();
        async.elapse(const Duration(seconds: 1));

        expect(answers.only.status, LiveQuestionStatus.answered);
        expect(questionOf(panel.last)?['state'], 'answered');
        expect(questionOf(panel.last)?['answer'], answers.only.answer);
        dispose(async);
      });
    });

    test('« ready » (panneau ouvert après le lancement) : l\'instantané '
        'entier repart, même inchangé', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(recordingState);
        async.elapse(const Duration(seconds: 1));
        final int before = panel.updates.length;
        final Map<Object?, Object?> shown = panel.last;

        fromPanel(async, 'ready');

        expect(panel.updates.length, before + 1);
        expect(panel.last, shown);
        dispose(async);
      });
    });

    test('la suggestion du shell apparaît puis disparaît dans le panneau', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        suggestion.show(
          const MeetingSuggestion(
            source: MeetingSource.call,
            key: 'call:us.zoom.xos',
            appName: 'Zoom',
          ),
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(
          (panel.last['suggestion'] as Map<Object?, Object?>?)?['detail'],
          'Zoom',
        );

        suggestion.show(null);
        async.elapse(const Duration(milliseconds: 500));
        expect(panel.last['suggestion'], isNull);
        dispose(async);
      });
    });

    test('une dictée qui commence est signalée', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        c.read(dictationActiveProvider.notifier).set(true);
        async.elapse(const Duration(milliseconds: 500));

        expect(panel.last['dictating'], isTrue);
        dispose(async);
      });
    });
  });

  group('robustesse', () {
    test('plugin natif absent : aucune erreur, le direct continue', () {
      fakeAsync((FakeAsync async) {
        mount(async, installPanel: false);

        live.show(recordingState);
        async.elapse(const Duration(seconds: 2));
        live.show(recordingState.copyWith(isPaused: true));
        async.elapse(const Duration(seconds: 2));

        expect(c.read(liveTranscriptionViewModelProvider).isPaused, isTrue);
        dispose(async);
      });
    });

    test('le canal lève une erreur : aucune erreur remontée, les envois '
        'suivants partent', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        panel.failUpdates = 2;

        live.show(recordingState);
        async.elapse(const Duration(seconds: 1));
        live.show(recordingState.copyWith(isPaused: true));
        async.elapse(const Duration(seconds: 1));
        live.show(recordingState);
        async.elapse(const Duration(seconds: 1));

        expect(panel.failUpdates, 0, reason: 'les échecs ont bien eu lieu');
        expect(panel.last['status'], 'recording');
        dispose(async);
      });
    });

    test('action inconnue du panneau : ignorée sans erreur', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'doSomethingElse', <String, Object?>{'x': 1});

        expect(live.startCalls, 0);
        dispose(async);
      });
    });
  });

  group('confidentialité', () {
    test('aucun modèle configuré : construire et envoyer l\'instantané ne '
        'déclenche aucune requête', () {
      fakeAsync((FakeAsync async) {
        mount(async, modelReady: false);
        live.show(recordingState);
        answers.hear(q);
        async.elapse(const Duration(seconds: 1));
        final int resolves = answers.resolveCalls;

        live.show(
          recordingState.copyWith(duration: const Duration(minutes: 3)),
        );
        async.elapse(const Duration(seconds: 1));
        fromPanel(async, 'ready');
        async.elapse(const Duration(seconds: 1));

        expect(questionOf(panel.last)?['state'], 'needsModel');
        expect(answers.resolveCalls, resolves);
        expect(answers.llm.requests, isEmpty);
        dispose(async);
      });
    });

    test('envoi coupé, modèle local : la question listée ne part nulle part '
        'tant qu\'on ne la demande pas', () {
      fakeAsync((FakeAsync async) {
        mount(async, localModel: true);
        live.show(recordingState);
        answers.hear(q);
        async.elapse(const Duration(seconds: 1));
        final int resolves = answers.resolveCalls;

        fromPanel(async, 'ready');
        live.show(
          recordingState.copyWith(duration: const Duration(minutes: 3)),
        );
        async.elapse(const Duration(seconds: 2));

        expect(questionOf(panel.last)?['state'], 'detected');
        expect(answers.resolveCalls, resolves);
        expect(answers.llm.requests, isEmpty);
        dispose(async);
      });
    });
  });

  group('actions du panneau', () {
    test('start : même chemin que « Nouvelle note » (le direct s\'affiche '
        'dans le shell, une note démarre)', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'start');

        expect(live.startCalls, 1);
        expect(c.read(shellViewControllerProvider), ShellView.live);
        expect(panel.last['status'], 'recording');
        dispose(async);
      });
    });

    test('start deux fois pendant que le démarrage est en vol : une seule '
        'note', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.startGate = Completer<void>();

        panel.send('start');
        panel.send('start');
        async.elapse(const Duration(milliseconds: 500));
        live.startGate!.complete();
        async.elapse(const Duration(milliseconds: 500));
        fromPanel(async, 'start');

        expect(live.startCalls, 1);
        dispose(async);
      });
    });

    test('start en pause : pas de seconde note', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(recordingState.copyWith(isPaused: true));

        fromPanel(async, 'start');

        expect(live.startCalls, 0);
        dispose(async);
      });
    });

    test('stop arrête la note en cours', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(recordingState);

        fromPanel(async, 'stop');

        expect(live.stopCalls, 1);
        expect(panel.last['status'], 'idle');
        dispose(async);
      });
    });

    test(
      'stop deux fois pendant l\'arrêt (vidange en cours) : un seul arrêt',
      () {
        fakeAsync((FakeAsync async) {
          mount(async);
          live.show(recordingState);
          live.stopGate = Completer<void>();

          panel.send('stop');
          panel.send('stop');
          async.elapse(const Duration(milliseconds: 500));
          panel.send('stop');
          async.elapse(const Duration(milliseconds: 500));
          live.stopGate!.complete();
          async.elapse(const Duration(milliseconds: 500));

          expect(live.stopCalls, 1);
          dispose(async);
        });
      },
    );

    test('stop pendant « Finalisation… » : pas de second arrêt', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(
          recordingState.copyWith(
            finalisingRemaining: const Duration(seconds: 20),
          ),
        );

        fromPanel(async, 'stop');

        expect(live.stopCalls, 0);
        dispose(async);
      });
    });

    test('stop au repos : rien', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'stop');

        expect(live.stopCalls, 0);
        dispose(async);
      });
    });

    test('pauseResume : pause pendant l\'enregistrement, reprise en pause, '
        'rien au repos', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        fromPanel(async, 'pauseResume');
        expect(live.pauseCalls + live.resumeCalls, 0);

        live.show(recordingState);
        fromPanel(async, 'pauseResume');
        expect(live.pauseCalls, 1);
        expect(panel.last['status'], 'paused');

        fromPanel(async, 'pauseResume');
        expect(live.resumeCalls, 1);
        expect(panel.last['status'], 'recording');
        dispose(async);
      });
    });

    test('skipFinalising pendant « Finalisation… »', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(
          recordingState.copyWith(
            finalisingRemaining: const Duration(seconds: 20),
          ),
        );

        fromPanel(async, 'skipFinalising');

        expect(live.skipCalls, 1);
        dispose(async);
      });
    });

    final CalendarEvent atelier = CalendarEvent(
      id: 'evt-atelier',
      title: 'Atelier roadmap',
      start: DateTime(2026, 11, 23, 10),
      end: DateTime(2026, 11, 23, 11),
      attendeeNames: const <String>['Personne A', 'Personne B'],
      attendeeCount: 2,
    );

    test('acceptSuggestion : comme « Démarrer la note » du shell, la note '
        'démarre liée à l\'événement affiché', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        suggestion.show(
          MeetingSuggestion(
            source: MeetingSource.calendar,
            key: 'event:evt-atelier',
            event: atelier,
          ),
        );
        async.elapse(const Duration(milliseconds: 500));

        fromPanel(async, 'acceptSuggestion');
        fromPanel(async, 'acceptSuggestion');

        expect(suggestion.startCalls, greaterThanOrEqualTo(1));
        expect(live.linked.map((CalendarEvent e) => e.id), <String>[
          'evt-atelier',
        ]);
        expect(live.startCalls, 1);
        expect(panel.last['suggestion'], isNull);
        dispose(async);
      });
    });

    test('acceptSuggestion sans suggestion (clic après sa disparition) : '
        'aucune note ne démarre', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'acceptSuggestion');

        expect(live.startCalls, 0);
        dispose(async);
      });
    });

    test('dismissSuggestion : comme « Ignorer » du shell (sourdine)', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        suggestion.show(
          const MeetingSuggestion(
            source: MeetingSource.call,
            key: 'call:us.zoom.xos',
            appName: 'Zoom',
          ),
        );
        async.elapse(const Duration(milliseconds: 500));

        fromPanel(async, 'dismissSuggestion');

        expect(suggestion.dismissCalls, 1);
        expect(c.read(meetingSuggestionControllerProvider), isNull);
        expect(panel.last['suggestion'], isNull);
        expect(live.startCalls, 0);
        dispose(async);
      });
    });

    test('answerNow : la question affichée part au modèle local, une seule '
        'fois même en double clic', () {
      fakeAsync((FakeAsync async) {
        mount(async, localModel: true);
        live.show(recordingState);
        answers.hear(q);
        async.elapse(const Duration(seconds: 1));
        final String id = questionOf(panel.last)!['id']! as String;
        expect(answers.llm.streams, isEmpty);

        panel.send('answerNow', <String, Object?>{'questionId': id});
        panel.send('answerNow', <String, Object?>{'questionId': id});
        async.elapse(const Duration(seconds: 1));

        expect(answers.llm.streams, hasLength(1));
        expect(questionOf(panel.last)?['state'], 'answering');
        dispose(async);
      });
    });

    test('answerNow pour une question qui n\'existe plus : rien ne part', () {
      fakeAsync((FakeAsync async) {
        mount(async, localModel: true);
        live.show(recordingState);
        answers.hear(q);
        async.elapse(const Duration(seconds: 1));

        fromPanel(async, 'answerNow', <String, Object?>{
          'questionId': 'q-gone',
        });

        expect(answers.llm.streams, isEmpty);
        dispose(async);
      });
    });

    test('openWindow : Dart demande au natif de montrer la fenêtre', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'openWindow');

        expect(panel.callsTo('showWindow'), hasLength(1));
        dispose(async);
      });
    });

    test('quit au repos : l\'app se termine', () {
      fakeAsync((FakeAsync async) {
        mount(async);

        fromPanel(async, 'quit');

        expect(panel.callsTo('terminate'), hasLength(1));
        expect(live.stopCalls, 0);
        dispose(async);
      });
    });

    test('quit pendant un enregistrement : la note s\'arrête et se sauve '
        'd\'abord, puis l\'app se termine', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        final List<String> log = <String>[];
        panel.log = log;
        live.log = log;
        live.show(recordingState);
        live.stopGate = Completer<void>();

        panel.send('quit');
        async.elapse(const Duration(seconds: 1));
        expect(panel.callsTo('terminate'), isEmpty, reason: 'arrêt en cours');

        live.stopGate!.complete();
        async.elapse(const Duration(seconds: 1));

        expect(live.stopCalls, 1);
        expect(log.where((String l) => l != 'panel.update').toList(), <String>[
          'live.stop',
          'live.stopped',
          'panel.terminate',
        ]);
        dispose(async);
      });
    });
  });
}
