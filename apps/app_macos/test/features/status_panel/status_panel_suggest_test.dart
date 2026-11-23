import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) : une suggestion de réunion se remarque
// pendant un appel dans une autre app, sans ouvrir le panneau. Pour chaque
// NOUVELLE suggestion (clé `MeetingSuggestion.key`, jamais deux fois la
// même), Dart envoie UN appel `suggest` en plus de l'instantané ; le natif
// ouvre alors le panneau sans activer l'app.
//
// Contenu de `suggest` : {`key`: String, `kind`: `calendar` | `call`,
// `title`: String, `detail`: String} (mêmes `kind`/`title`/`detail` que la
// clé `suggestion` de l'instantané).
// Jamais pendant un enregistrement (pause et finalisation comprises) ni
// pendant une dictée ; jamais de nouveau après « Ignorer » tant que la clé
// est la même ; envoyé aussi quand la fenêtre principale est masquée.
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  late FakeStatusPanelPlatform panel;
  late PanelLiveViewModel live;
  late PanelSuggestionController suggestion;
  late ProviderContainer c;

  final CalendarEvent atelier = CalendarEvent(
    id: 'evt-atelier',
    title: 'Atelier roadmap',
    start: DateTime(2026, 11, 23, 10),
    end: DateTime(2026, 11, 23, 10, 30),
    attendeeCount: 3,
  );
  final MeetingSuggestion calendar = MeetingSuggestion(
    source: MeetingSource.calendar,
    key: 'event:evt-atelier',
    event: atelier,
  );
  const MeetingSuggestion zoom = MeetingSuggestion(
    source: MeetingSource.call,
    key: 'call:us.zoom.xos',
    appName: 'Zoom',
    bundleId: 'us.zoom.xos',
  );

  void mount(FakeAsync async) {
    panel = FakeStatusPanelPlatform()..install();
    live = PanelLiveViewModel();
    suggestion = PanelSuggestionController();
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionViewModelProvider.overrideWith(() => live),
        meetingSuggestionControllerProvider.overrideWith(() => suggestion),
        liveAnswersServiceProvider.overrideWithValue(
          LiveAnswersHarness().service,
        ),
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

  void showSuggestion(FakeAsync async, MeetingSuggestion? s) {
    suggestion.show(s);
    async.elapse(const Duration(milliseconds: 500));
  }

  List<MethodCall> suggests() => panel.callsTo('suggest');

  final LiveTranscriptionState recording = LiveTranscriptionState.initial()
      .copyWith(isRecording: true, sessionTitle: 'Revue de sprint');

  test('événement d\'agenda : un appel `suggest` avec clé, titre et '
      'horaires', () {
    fakeAsync((FakeAsync async) {
      mount(async);

      showSuggestion(async, calendar);

      expect(suggests(), hasLength(1));
      expect(suggests().single.arguments, <String, Object?>{
        'key': 'event:evt-atelier',
        'kind': 'calendar',
        'title': 'Atelier roadmap',
        'detail': '10:00–10:30',
      });
      expect(
        (panel.last['suggestion'] as Map<Object?, Object?>?)?['title'],
        'Atelier roadmap',
        reason: 'l\'instantané porte aussi la suggestion',
      );
      dispose(async);
    });
  });

  test('appel détecté : `suggest` avec le nom de l\'app', () {
    fakeAsync((FakeAsync async) {
      mount(async);

      showSuggestion(async, zoom);

      final Map<Object?, Object?> args =
          suggests().single.arguments as Map<Object?, Object?>;
      expect(args['key'], 'call:us.zoom.xos');
      expect(args['kind'], 'call');
      expect(args['detail'], 'Zoom');
      expect(args['title'], isA<String>());
      expect(args['title'], isNotEmpty);
      dispose(async);
    });
  });

  test('la même clé jamais deux fois (instantanés répétés, `ready`, '
      'réapparition)', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      showSuggestion(async, zoom);

      panel.send('ready');
      async.elapse(const Duration(milliseconds: 500));
      showSuggestion(async, null);
      showSuggestion(async, zoom);

      expect(suggests(), hasLength(1));
      dispose(async);
    });
  });

  test('une nouvelle clé : un nouvel appel', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      showSuggestion(async, zoom);

      showSuggestion(async, calendar);

      expect(
        suggests().map((MethodCall m) => (m.arguments as Map)['key']),
        <Object?>['call:us.zoom.xos', 'event:evt-atelier'],
      );
      dispose(async);
    });
  });

  test('après « Ignorer » : rien tant que la clé est la même, une nouvelle '
      'clé repart', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      showSuggestion(async, zoom);

      panel.send('dismissSuggestion');
      async.elapse(const Duration(milliseconds: 500));
      showSuggestion(async, zoom);
      expect(suggests(), hasLength(1));

      showSuggestion(async, calendar);
      expect(suggests(), hasLength(2));
      dispose(async);
    });
  });

  for (final (String name, LiveTranscriptionState state)
      in <(String, LiveTranscriptionState)>[
        ('un enregistrement', recording),
        ('une pause', recording.copyWith(isPaused: true)),
        (
          'une finalisation',
          LiveTranscriptionState.initial().copyWith(
            finalisingRemaining: const Duration(seconds: 30),
          ),
        ),
      ]) {
    test('pendant $name : aucun `suggest`', () {
      fakeAsync((FakeAsync async) {
        mount(async);
        live.show(state);
        async.elapse(const Duration(milliseconds: 500));

        showSuggestion(async, zoom);

        expect(suggests(), isEmpty);
        dispose(async);
      });
    });
  }

  test('pendant une dictée : aucun `suggest`', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      c.read(dictationActiveProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 500));

      showSuggestion(async, zoom);

      expect(suggests(), isEmpty);
      dispose(async);
    });
  });

  test('fenêtre principale masquée : `suggest` part quand même', () {
    fakeAsync((FakeAsync async) {
      addTearDown(() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      mount(async);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      async.elapse(const Duration(milliseconds: 500));

      showSuggestion(async, calendar);

      expect(suggests(), hasLength(1));
      dispose(async);
    });
  });

  test('canal en erreur pour `suggest` : rien ne remonte, l\'instantané '
      'part quand même', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      panel.onCall = (MethodCall call) {
        if (call.method == 'suggest') {
          throw PlatformException(code: 'PANEL_UNAVAILABLE');
        }
      };

      showSuggestion(async, zoom);

      expect(
        (panel.last['suggestion'] as Map<Object?, Object?>?)?['detail'],
        'Zoom',
      );
      dispose(async);
    });
  });
}
