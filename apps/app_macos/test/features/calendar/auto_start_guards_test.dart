import 'dart:async';
import 'dart:convert';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_prefs.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoins 5 et 6 (revue PR #22) :
// - jamais une seconde note pour une réunion qui en a déjà une : au
//   lancement, tant que la liste des notes n'est pas connue, ni démarrage
//   automatique (mode auto) ni suggestion (mode demander) pour un événement
//   en cours ; une fois la liste connue, toujours rien (la note existe) ;
// - un démarrage automatique qui échoue (serveur qui ne démarre pas, micro
//   refusé) n'est pas silencieux. Comportement fixé : la suggestion de
//   l'événement est alors affichée (comme en mode demander), pour que
//   l'utilisateur puisse réessayer avec « Démarrer la note » ou ignorer.
//
// Vrai contrôleur de suggestion, vrai view model du direct (faux serveur,
// fausse capture), vraie liste des notes sur un dépôt dont la lecture est
// retenue. Attentes sur des événements, bornées à 10 s ; « rien ne se
// passe » = plusieurs évaluations du contrôleur (chacune lit l'horloge)
// une fois réglages et agenda chargés.
final class _GatedSessions implements SessionRepository {
  _GatedSessions(this.sessions);

  final List<SessionEntity> sessions;
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<SessionEntity>> getAll() async {
    await gate.future;
    return sessions;
  }

  @override
  Stream<List<SessionEntity>> watchAll() async* {
    await gate.future;
    yield sessions;
  }

  @override
  Future<SessionEntity?> getById(String id) async {
    await gate.future;
    return sessions.where((SessionEntity s) => s.id == id).firstOrNull;
  }

  @override
  Future<SessionEntity> create(SessionEntity session) async => session;
  @override
  Future<SessionEntity> update(SessionEntity session) async => session;
  @override
  Future<void> delete(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPrefs);
  tearDown(resetPrefs);

  const Duration bound = Duration(seconds: 10);
  final DateTime t0 = DateTime(2026, 11, 23, 10);
  late LiveServiceHarness harness;
  late ProviderContainer c;
  int clockReads = 0;

  void writePrefs(Map<String, Object?> prefs) {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync(jsonEncode(prefs));
  }

  Map<String, Object?> atelier() => eventJson(
    id: 'evt-atelier',
    title: 'Atelier stratégie',
    start: t0.subtract(const Duration(minutes: 5)),
    end: t0.add(const Duration(minutes: 55)),
    attendees: <String>['Alice Martin', 'Bruno Petit'],
  );

  final SessionEntity existingNote = SessionEntity(
    id: 'note-atelier',
    title: 'Atelier stratégie',
    createdAt: t0.subtract(const Duration(minutes: 4)),
    updatedAt: t0.subtract(const Duration(minutes: 4)),
    status: SessionStatus.interrupted,
    calendarEventId: 'evt-atelier',
    calendarEventTitle: 'Atelier stratégie',
  );

  Future<void> launch({
    required String mode,
    required _GatedSessions history,
    void Function(LiveServiceHarness h)? arrange,
  }) async {
    writePrefs(<String, Object?>{
      'calendar_connected': true,
      'meeting_detection_mode': mode,
    });
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[atelier()],
    ).install();
    FakeMeetingPlatform().install();
    clockReads = 0;
    harness = LiveServiceHarness(FakeAsync());
    arrange?.call(harness);
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(harness.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: harness.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        nowProvider.overrideWithValue(() {
          clockReads++;
          return t0;
        }),
        sessionRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(c.dispose);
    // Liste des notes rendue avant la fin du test : aucun chargement en
    // retard ne touche un conteneur déjà libéré.
    addTearDown(() async {
      if (!history.gate.isCompleted) history.gate.complete();
      await eventually(
        () => expect(
          c.read(sessionListViewModelProvider).sessions,
          hasLength(history.sessions.length),
        ),
        timeout: bound,
      );
    });
    addTearDown(() => harness.service.stopTranscription());
    c.read(liveTranscriptionViewModelProvider);
    c.listen(sessionListViewModelProvider, (_, _) {});
    c.listen(meetingSuggestionControllerProvider, (_, _) {});
    await c.read(calendarPrefsControllerProvider.future);
    await c.read(calendarFeedControllerProvider.future);
  }

  MeetingSuggestion? shown() => c.read(meetingSuggestionControllerProvider);

  /// Au moins [n] lectures d'horloge de plus (≈ évaluations du contrôleur).
  Future<void> evaluations(int n) async {
    final int target = clockReads + n;
    await eventually(
      () => expect(clockReads, greaterThanOrEqualTo(target)),
      timeout: bound,
    );
  }

  group('une note existe déjà pour l\'événement en cours', () {
    for (final String mode in <String>['auto', 'ask']) {
      test('mode $mode : rien tant que la liste des notes n\'est pas connue, '
          'ni après', () async {
        final _GatedSessions history = _GatedSessions(<SessionEntity>[
          existingNote,
        ]);
        await launch(mode: mode, history: history);

        await evaluations(4);
        expect(harness.sessions.store, isEmpty, reason: 'liste inconnue');
        expect(shown(), isNull, reason: 'liste inconnue');

        history.gate.complete();
        await eventually(
          () =>
              expect(c.read(sessionListViewModelProvider).sessions, isNotEmpty),
          timeout: bound,
        );
        await evaluations(4);

        expect(harness.sessions.store, isEmpty, reason: 'liste connue');
        expect(shown(), isNull, reason: 'liste connue');
      });
    }
  });

  group('démarrage automatique qui échoue', () {
    Future<void> launchAuto(void Function(LiveServiceHarness h) arrange) =>
        launch(
          mode: 'auto',
          arrange: arrange,
          history: _GatedSessions(const <SessionEntity>[])..gate.complete(),
        );

    test('serveur qui ne démarre pas : la suggestion de l\'événement '
        's\'affiche', () async {
      await launchAuto((LiveServiceHarness h) => h.process.failStarts = true);
      // Le démarrage automatique a bien eu lieu et a échoué.
      await eventually(
        () => expect(
          c.read(liveTranscriptionViewModelProvider).serverState,
          ServerState.error,
        ),
        timeout: bound,
      );

      await eventually(
        () => expect(shown()?.event?.id, 'evt-atelier'),
        timeout: bound,
      );
      expect(c.read(liveTranscriptionViewModelProvider).isRecording, isFalse);
    });

    test('micro refusé : la suggestion de l\'événement s\'affiche', () async {
      await launchAuto(
        (LiveServiceHarness h) => h.audio.startError = PlatformException(
          code: 'MIC_PERMISSION_DENIED',
        ),
      );
      await eventually(
        () => expect(
          c.read(liveTranscriptionViewModelProvider).micPermission,
          'denied',
        ),
        timeout: bound,
      );

      await eventually(
        () => expect(shown()?.event?.id, 'evt-atelier'),
        timeout: bound,
      );
      expect(c.read(liveTranscriptionViewModelProvider).isRecording, isFalse);
    });
  });
}
