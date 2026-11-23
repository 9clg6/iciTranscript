import 'dart:async';
import 'dart:io';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/process_host_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) : quitter. `quit` vient du panneau, et
// aussi de ⌘Q et Dock › Quitter (le natif route la demande du système vers
// la même action). Ordre épinglé : arrêter la note (sauvée) → arrêter les
// serveurs lancés par Oats (tout le registre des processus : un serveur de
// modèle de plusieurs Go ne survit pas à l'app) → `terminate`.
//
// Choix : quitter PASSE la finalisation (l'audio est sur disque, le
// rattrapage reprend au lancement suivant) ; quitter ne prend jamais des
// minutes. Borne : `terminate` part au plus 30 s après `quit`, même si
// l'arrêt de la note reste bloqué et qu'un serveur ignore SIGTERM (le
// registre attend 5 s avant SIGKILL, puis le port, d'où la marge).
// Idempotent : plusieurs `quit` → un arrêt, un `terminate`.
//
// Faux : direct (compte les actions), panneau natif, hôte de processus
// (aucun vrai processus). Temps simulé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Duration bound = Duration(seconds: 30);

  late FakeStatusPanelPlatform panel;
  late QuitLiveViewModel live;
  late FakeProcessHost host;
  late OwnedProcessRegistry registry;
  late ProviderContainer c;
  late Directory dir;
  late List<int> servers;

  /// État noté au moment du `terminate`.
  ({Duration at, Set<int> alive, int stops, List<String> log})? atTerminate;

  final LiveTranscriptionState recordingState = LiveTranscriptionState.initial()
      .copyWith(
        isRecording: true,
        duration: const Duration(minutes: 2),
        sessionTitle: 'Revue de sprint',
      );

  void mount(FakeAsync async, {ProcessHost Function(FakeProcessHost)? wrap}) {
    dir = Directory.systemTemp.createTempSync('status_panel_quit_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    host = FakeProcessHost();
    registry = OwnedProcessRegistry(
      host: wrap == null ? host : wrap(host),
      stateFile: '${dir.path}/servers.json',
    );
    servers = <int>[];
    // Le serveur de transcription et un autre serveur du registre.
    registry
        .start('transcription', 'uvx', <String>['voxmlx-serve'], port: 8100)
        .then((Process p) => servers.add(p.pid));
    registry
        .start('llm', 'ollama', <String>['serve'], port: 11434)
        .then((Process p) => servers.add(p.pid));
    async.flushMicrotasks();
    expect(servers, hasLength(2), reason: 'deux serveurs lancés');

    atTerminate = null;
    panel = FakeStatusPanelPlatform()..install();
    live = QuitLiveViewModel();
    final List<String> log = <String>[];
    panel.log = log;
    live.log = log;
    panel.onCall = (MethodCall call) {
      if (call.method != 'terminate' || atTerminate != null) return;
      atTerminate = (
        at: async.elapsed,
        alive: servers.where(host.table.containsKey).toSet(),
        stops: live.stopCalls,
        log: List<String>.of(log),
      );
    };
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionViewModelProvider.overrideWith(() => live),
        meetingSuggestionControllerProvider.overrideWith(
          PanelSuggestionController.new,
        ),
        liveAnswersServiceProvider.overrideWithValue(
          LiveAnswersHarness().service,
        ),
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(const <SessionEntity>[]),
        ),
        ownedProcessRegistryProvider.overrideWithValue(registry),
      ],
    );
    c.listen(statusPanelSyncProvider, (_, _) {});
    async.elapse(const Duration(seconds: 1));
  }

  void dispose(FakeAsync async) {
    c.dispose();
    async.flushMicrotasks();
  }

  /// `quit` du panneau ; renvoie l'heure (simulée) de la demande.
  Duration quit(FakeAsync async) {
    final Duration at = async.elapsed;
    panel.send('quit');
    async.flushMicrotasks();
    return at;
  }

  test('au repos : les serveurs lancés par Oats s\'arrêtent, puis l\'app se '
      'termine', () {
    fakeAsync((FakeAsync async) {
      mount(async);

      quit(async);
      async.elapse(bound);

      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.alive, isEmpty, reason: 'serveurs arrêtés avant');
      expect(live.stopCalls, 0);
      dispose(async);
    });
  });

  test('pendant une note : note arrêtée et sauvée → serveurs arrêtés → '
      'terminate', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      live.show(recordingState);
      live.stopGate = Completer<void>();
      // Pas de finalisation ici : seul le complètement de l'arrêt compte.
      live.skipReleasesStop = false;

      quit(async);
      async.elapse(const Duration(seconds: 1));
      expect(live.stopCalls, 1);
      expect(
        host.killedPids,
        isEmpty,
        reason: 'aucun serveur arrêté tant que la note n\'est pas sauvée',
      );
      expect(panel.callsTo('terminate'), isEmpty);

      live.stopGate!.complete();
      async.elapse(bound);

      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.alive, isEmpty);
      expect(
        atTerminate!.log.where((String l) => l.startsWith('live.')),
        <String>['live.stop', 'live.stopped'],
      );
      dispose(async);
    });
  });

  test('quitter pendant une note passe la finalisation (pas d\'attente de '
      'minutes)', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      live.show(recordingState);
      live.stopGate = Completer<void>();
      // Arrêter vide l'audio restant : 2 min d'audio à transcrire.
      live.drainOnStop = const Duration(minutes: 2);

      final Duration asked = quit(async);
      async.elapse(bound);

      expect(live.skipCalls, greaterThanOrEqualTo(1));
      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.at - asked, lessThanOrEqualTo(bound));
      expect(atTerminate!.stops, 1);
      expect(atTerminate!.log, contains('live.stopped'));
      dispose(async);
    });
  });

  test('quitter pendant une finalisation lancée depuis la fenêtre : elle est '
      'passée, pas de second arrêt, puis terminate', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      live.show(
        LiveTranscriptionState.initial().copyWith(
          finalisingRemaining: const Duration(minutes: 2),
        ),
      );

      final Duration asked = quit(async);
      async.elapse(bound);

      expect(live.skipCalls, greaterThanOrEqualTo(1));
      expect(live.stopCalls, 0);
      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.at - asked, lessThanOrEqualTo(bound));
      expect(atTerminate!.alive, isEmpty);
      dispose(async);
    });
  });

  test('idempotent : deux quit de suite (panneau puis ⌘Q) → un arrêt, un '
      'terminate, chaque serveur signalé une fois', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      live.show(recordingState);
      live.stopGate = Completer<void>();

      quit(async);
      quit(async);
      async.elapse(const Duration(seconds: 1));
      live.stopGate!.complete();
      async.elapse(bound);
      quit(async);
      async.elapse(bound);

      expect(live.stopCalls, 1);
      expect(panel.callsTo('terminate'), hasLength(1));
      expect(
        host.groupKills
            .where((k) => k.signal == ProcessSignal.sigterm)
            .map((k) => k.groupId),
        unorderedEquals(servers),
      );
      dispose(async);
    });
  });

  test('l\'arrêt de la note reste bloqué et un serveur ignore SIGTERM : '
      'terminate part quand même dans la borne, serveurs arrêtés', () {
    fakeAsync((FakeAsync async) {
      mount(async);
      host.ignoreSigterm = true;
      live.show(recordingState);
      live.stopGate = Completer<void>(); // jamais complété
      live.skipReleasesStop = false;

      final Duration asked = quit(async);
      async.elapse(const Duration(seconds: 60));

      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.at - asked, lessThanOrEqualTo(bound));
      expect(atTerminate!.alive, isEmpty);
      dispose(async);
    });
  });

  test('un serveur qu\'on ne peut pas arrêter (erreur du système) '
      'n\'empêche ni l\'arrêt des autres ni la fin de l\'app', () {
    fakeAsync((FakeAsync async) {
      late FailingKillHost failing;
      mount(async, wrap: (FakeProcessHost h) => failing = FailingKillHost(h));
      failing.failingGroup = servers.first;

      final Duration asked = quit(async);
      async.elapse(bound);

      expect(panel.callsTo('terminate'), hasLength(1));
      expect(atTerminate!.at - asked, lessThanOrEqualTo(bound));
      expect(host.table.containsKey(servers.last), isFalse);
      dispose(async);
    });
  });
}

/// Direct factice pour quitter : l'arrêt peut vider de l'audio restant
/// (« Finalisation… ») jusqu'à `skipFinalising`, comme le vrai.
class QuitLiveViewModel extends PanelLiveViewModel {
  /// Audio restant affiché pendant l'arrêt ; null = pas de finalisation.
  Duration? drainOnStop;

  /// `skipFinalising` termine l'arrêt en cours (vrai comportement).
  bool skipReleasesStop = true;

  @override
  Future<String?> stopSession() {
    final Duration? drain = drainOnStop;
    if (drain != null) {
      // L'état passe en finalisation juste après la demande d'arrêt.
      scheduleMicrotask(
        () => show(current.copyWith(finalisingRemaining: drain)),
      );
    }
    return super.stopSession();
  }

  @override
  void skipFinalising() {
    super.skipFinalising();
    if (!skipReleasesStop) return;
    final Completer<void>? gate = stopGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    } else if (gate == null && current.finalisingRemaining != null) {
      // Finalisation lancée depuis la fenêtre : elle se termine.
      scheduleMicrotask(
        () => show(
          current.copyWith(
            finalisingRemaining: null,
            isRecording: false,
            isPaused: false,
          ),
        ),
      );
    }
  }
}

/// Hôte qui lève une erreur en signalant un groupe donné ; le reste passe
/// au faux habituel.
final class FailingKillHost implements ProcessHost {
  FailingKillHost(this._d);

  final FakeProcessHost _d;

  /// Groupe (= PID du meneur) dont le signal échoue.
  int? failingGroup;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => _d.start(executable, arguments, environment: environment, mode: mode);

  @override
  Future<List<RunningProcess>> running() => _d.running();

  @override
  bool kill(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (pid == failingGroup) {
      throw const ProcessException(
        'kill',
        <String>[],
        'Operation not permitted',
      );
    }
    return _d.kill(pid, signal);
  }

  @override
  bool killGroup(int groupId, [ProcessSignal signal = ProcessSignal.sigterm]) {
    if (groupId == failingGroup) {
      throw const ProcessException(
        'kill',
        <String>[],
        'Operation not permitted',
      );
    }
    return _d.killGroup(groupId, signal);
  }

  @override
  int get appGroupId => _d.appGroupId;

  @override
  Future<bool> isPortFree(int port) => _d.isPortFree(port);

  @override
  Future<bool> isHealthy(Uri url) => _d.isHealthy(url);
}
