import 'dart:async';
import 'dart:convert';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) : démarrer une note fenêtre principale
// masquée, le cas d'usage principal du panneau. Rien ne doit attendre une
// image (frame) ni une route : l'enregistrement démarre (état « enregistre »,
// session créée) sans qu'aucune image ne soit dessinée ; la navigation vers
// le direct n'est qu'un état du shell (`ShellView.live`), affiché quand la
// fenêtre revient.
//
// Simulation de la fenêtre masquée : cycle de vie passé à `inactive` puis
// `hidden` (`handleAppLifecycleStateChanged`), ce qui coupe les images
// (`framesEnabled` faux) ; tests `test()` simples, sans arbre de widgets ni
// `pump` : aucune image n'est jamais produite.
//
// Vrai view model du direct, vrai LiveTranscriptionService (serveur, micro,
// socket factices), vrai canal du panneau (natif factice).
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  late LiveServiceHarness live;
  late FakeStatusPanelPlatform panel;
  late ProviderContainer c;
  late DateTime now;
  late PanelSuggestionController? fakeSuggestion;

  Future<void> soon(FutureOr<void> Function() check) =>
      eventually(check, timeout: const Duration(seconds: 10));

  void hideWindow() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(binding.framesEnabled, isFalse, reason: 'plus aucune image');
  }

  setUp(() {
    resetPrefs();
    now = DateTime(2026, 11, 23, 10);
    fakeSuggestion = null;
    addTearDown(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  /// Monte l'app sans fenêtre ; [realSuggestions] : vrai contrôleur de
  /// suggestion (agenda, démarrage automatique), sinon un faux à piloter.
  void launch({bool realSuggestions = false}) {
    panel = FakeStatusPanelPlatform()..install();
    live = LiveServiceHarness(FakeAsync());
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(live.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: live.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        databaseProvider.overrideWithValue(memoryDatabase()),
        liveAnswersServiceProvider.overrideWithValue(
          LiveAnswersHarness().service,
        ),
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(const <SessionEntity>[]),
        ),
        nowProvider.overrideWithValue(() => now),
        if (!realSuggestions)
          meetingSuggestionControllerProvider.overrideWith(
            () => fakeSuggestion = PanelSuggestionController(),
          ),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(() => live.service.stopTranscription());
    c.read(liveTranscriptionViewModelProvider.notifier);
    c.listen(statusPanelSyncProvider, (_, _) {});
    c.listen(meetingSuggestionControllerProvider, (_, _) {});
  }

  void expectRecordingStarted() {
    expect(c.read(liveTranscriptionViewModelProvider).isRecording, isTrue);
    expect(live.service.isRecording, isTrue);
    expect(live.sessions.store.values, hasLength(1));
  }

  test('« start » du panneau, fenêtre masquée : la note enregistre sans '
      'image ; le shell montrera le direct au retour de la fenêtre', () async {
    launch();
    hideWindow();
    await soon(() => expect(panel.updates, isNotEmpty));

    await panel.send('start');

    await soon(expectRecordingStarted);
    expect(c.read(shellViewControllerProvider), ShellView.live);
    await soon(() => expect(panel.last['status'], 'recording'));
    expect(binding.framesEnabled, isFalse);
  });

  test('« acceptSuggestion », fenêtre masquée : la note enregistre, liée à '
      'l\'événement', () async {
    launch();
    hideWindow();
    final CalendarEvent event = CalendarEvent(
      id: 'evt-revue',
      title: 'Revue trimestrielle',
      start: now,
      end: now.add(const Duration(hours: 1)),
      attendeeNames: const <String>['Personne A', 'Personne B'],
      attendeeCount: 2,
    );
    fakeSuggestion!.show(
      MeetingSuggestion(
        source: MeetingSource.calendar,
        key: 'event:evt-revue',
        event: event,
      ),
    );
    await soon(() => expect(panel.last['suggestion'], isNotNull));

    await panel.send('acceptSuggestion');

    await soon(expectRecordingStarted);
    final SessionEntity s = live.sessions.store.values.single;
    expect(s.calendarEventId, 'evt-revue');
    expect(s.title, 'Revue trimestrielle');
    expect(binding.framesEnabled, isFalse);
  });

  test('démarrage automatique d\'un événement d\'agenda, fenêtre masquée : '
      'la note enregistre, liée à l\'événement', () async {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'calendar_connected': true,
        'meeting_detection_mode': 'auto',
      }),
    );
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[
        eventJson(
          id: 'evt-atelier',
          title: 'Atelier stratégie',
          start: now.subtract(const Duration(minutes: 2)),
          end: now.add(const Duration(minutes: 58)),
          attendees: <String>['Personne A', 'Personne B'],
        ),
      ],
    ).install();
    FakeMeetingPlatform().install();
    hideWindow();

    launch(realSuggestions: true);

    await soon(expectRecordingStarted);
    expect(
      live.sessions.store.values.single.calendarEventId,
      'evt-atelier',
    );
    expect(binding.framesEnabled, isFalse);
  });
}
