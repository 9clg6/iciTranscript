import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/platform/owned_processes.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/process_host_fakes.dart' show FakeProcessHost;
import '../../helpers/settings_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3), revue de la PR #24 : quitter ne doit pas
// perdre le texte passé. `quit` passe la finalisation en promettant que le
// rattrapage reprend au lancement suivant, puis arrête le serveur
// (`OwnedProcessRegistry.stopAll`). Avec les VRAIS services (direct,
// GapBackfillService, GapBackfillRetry et son `.backfill_pending.json`),
// serveur de transcription et hôte de processus factices :
// - avant `terminate`, la session est notée en attente sur le disque ;
// - la tentative coupée par la fin de l'app ne compte pas parmi les trois ;
// - au lancement suivant (`retryPending`, serveur qui répond), la phrase
//   revient, une fois, à son heure, et le repère de perte disparaît.
//
// La fin du processus est jouée ainsi : l'état du disque au moment du
// `terminate` est celui que lit le lancement suivant (rien n'écrit après).
// Temps réel, dossier temporaire de test, aucun réseau.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String lost = 'Le devis part vendredi.';
  // Phrase perdue entre 10 et 20 s de réunion (repère de perte).
  const int gapStart = 10000;
  const int gapEnd = 20000;

  setUp(() async {
    resetPrefs();
    final Directory d = Directory(LiveTranscriptionService.recordingsDir);
    expect(d.path, startsWith(Directory.systemTemp.path));
    for (int i = 0; i < 5 && d.existsSync(); i++) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    await d.create(recursive: true);
  });

  File pendingFile() =>
      File('${LiveTranscriptionService.recordingsDir}/.backfill_pending.json');

  /// [windowStopFirst] : la note est arrêtée depuis la fenêtre et le
  /// rattrapage a atteint le serveur (sans réponse) quand `quit` arrive ;
  /// sinon `quit` arrive pendant l'enregistrement.
  Future<void> scenario({required bool windowStopFirst}) async {
    // --- Premier lancement ---------------------------------------------
    final FakeProcessHost host = FakeProcessHost();
    final Directory stateDir = Directory.systemTemp.createTempSync(
      'quit_backfill_state_',
    );
    addTearDown(() => stateDir.deleteSync(recursive: true));
    final OwnedProcessRegistry registry = OwnedProcessRegistry(
      host: host,
      stateFile: '${stateDir.path}/servers.json',
    );
    final Process server = await registry.start(
      'transcription',
      'uvx',
      <String>['voxmlx-serve'],
      port: 8100,
    );
    // Le serveur de rattrapage ne répond pas (phrase sans réponse) et meurt
    // quand le registre l'arrête.
    final _BackfillServer first = _BackfillServer(
      reply: null,
      alive: () => host.table.containsKey(server.pid),
    );
    final _Rig rig = _Rig(backfillServer: first);

    final FakeStatusPanelPlatform panel = FakeStatusPanelPlatform()..install();
    String? pendingAtTerminate;
    panel.onCall = (MethodCall call) {
      if (call.method != 'terminate' || pendingAtTerminate != null) return;
      pendingAtTerminate = pendingFile().existsSync()
          ? pendingFile().readAsStringSync()
          : '';
    };
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(rig.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: rig.process),
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
        ownedProcessRegistryProvider.overrideWithValue(registry),
      ],
    );
    c.read(liveTranscriptionViewModelProvider.notifier);
    c.listen(statusPanelSyncProvider, (_, _) {});

    await c.read(liveTranscriptionViewModelProvider.notifier).startSession();
    final String sessionId = rig.sessionId;
    await rig.speak(0, 300); // 30 s de micro dans le WAV
    rig.gap(gapStart, gapEnd);
    await rig.until(() => rig.markersOf(sessionId).isNotEmpty);
    expect(rig.markersOf(sessionId), hasLength(1));

    if (windowStopFirst) {
      unawaited(
        c.read(liveTranscriptionViewModelProvider.notifier).stopSession(),
      );
      await rig.until(() => first.commits > 0);
      expect(first.commits, greaterThan(0), reason: 'rattrapage en vol');
    }
    await panel.send('quit');
    await rig.until(
      () => panel.callsTo('terminate').isNotEmpty,
      within: const Duration(seconds: 40),
    );

    expect(panel.callsTo('terminate'), hasLength(1));
    expect(host.table.containsKey(server.pid), isFalse, reason: 'tué');
    expect(
      pendingAtTerminate,
      isNotEmpty,
      reason: 'la session doit être notée en attente AVANT terminate',
    );
    final Map<String, dynamic> pending =
        jsonDecode(pendingAtTerminate!) as Map<String, dynamic>;
    expect(
      pending[sessionId],
      0,
      reason: 'la tentative coupée par la fin de l\'app ne compte pas',
    );

    // Fin du processus : plus rien ne tourne, le disque est celui du
    // terminate.
    first.endOfProcess();
    c.dispose();
    await rig.dispose();
    await pendingFile().writeAsString(pendingAtTerminate!);

    // --- Lancement suivant ---------------------------------------------
    final _BackfillServer second = _BackfillServer(reply: lost);
    final GapBackfillRetry relaunch = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: WebSocketPcmTranscriber(
          url: 'ws://test',
          createClient: second.client,
          shouldYield: () => false,
        ),
        transcripts: rig.segments,
        isRecording: () => false,
      ),
      serverStates: const Stream<ServerState>.empty(),
      isRecording: () => false,
      recordingsDirectory: LiveTranscriptionService.recordingsDir,
    );
    addTearDown(relaunch.dispose);

    await relaunch.retryPending();

    expect(rig.markersOf(sessionId), isEmpty, reason: 'repère remplacé');
    final List<TranscriptSegmentEntity> back = rig.segments.store.values
        .where(
          (TranscriptSegmentEntity s) =>
              s.sessionId == sessionId && s.text == lost,
        )
        .toList();
    expect(back, hasLength(1), reason: 'la phrase revient, une fois');
    expect(
      back.single.timestampMs,
      inInclusiveRange(
        gapStart - GapBackfillService.margin.inMilliseconds,
        gapEnd,
      ),
      reason: 'à son heure dans la réunion',
    );
    expect(pendingFile().existsSync(), isFalse, reason: 'plus rien en attente');
  }

  test('quitter pendant un enregistrement avec une perte : session en '
      'attente sur le disque avant terminate, sans tentative comptée ; la '
      'phrase revient au lancement suivant', () async {
    await scenario(windowStopFirst: false);
  });

  test(
    'quitter pendant le rattrapage de l\'arrêt (serveur atteint, sans '
    'réponse) : la tentative coupée ne compte pas, la session est en '
    'attente avant terminate ; la phrase revient au lancement suivant',
    () async {
      await scenario(windowStopFirst: true);
    },
  );
}

/// Direct réel monté sur des faux, rattrapage réel par
/// WebSocketPcmTranscriber sur [backfillServer] (comme
/// back_to_back_meetings_test.dart).
final class _Rig {
  _Rig({required this.backfillServer}) {
    transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: segments,
      ),
    );
    bool recording() => transcription.isTranscribingStream.value;
    retry = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: WebSocketPcmTranscriber(
          url: 'ws://test',
          createClient: backfillServer.client,
          shouldYield: recording,
        ),
        transcripts: segments,
        isRecording: recording,
      ),
      serverStates: process.stateStream,
      isRecording: recording,
      recordingsDirectory: LiveTranscriptionService.recordingsDir,
    );
    service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(channel: process),
      audioCaptureChannel: audio,
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      gapBackfillRetry: retry,
    );
  }

  final _BackfillServer backfillServer;
  final FakeTranscriptionRemoteDataSource remote =
      FakeTranscriptionRemoteDataSource();
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  final InMemoryTranscriptRepository segments = InMemoryTranscriptRepository();
  late final TranscriptionService transcription;
  late final GapBackfillRetry retry;
  late final LiveTranscriptionService service;

  Future<void> dispose() async {
    await retry.dispose();
    await service.dispose();
  }

  String get sessionId => transcription.currentSessionStream.value!.id;
  int get t0 => transcription
      .currentSessionStream
      .value!
      .createdAt
      .millisecondsSinceEpoch;

  Future<void> speak(int fromId, int count) async {
    for (int id = fromId; id < fromId + count; id++) {
      audio.emit(chunk(AudioSource.input, id, timestampMs: t0 + id * 100));
      if (id % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  void gap(int startMs, int endMs) => remote.emitGap(
    AudioGap(
      source: AudioSource.input,
      startMs: t0 + startMs,
      endMs: t0 + endMs,
    ),
  );

  List<TranscriptSegmentEntity> markersOf(String sessionId) => segments
      .store
      .values
      .where(
        (TranscriptSegmentEntity s) =>
            s.sessionId == sessionId &&
            (s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
                LiveTranscriptionService.isUntranscribedMarker(s.text)),
      )
      .toList();

  Future<void> until(
    bool Function() condition, {
    Duration within = const Duration(seconds: 10),
  }) async {
    final Stopwatch w = Stopwatch()..start();
    while (!condition() && w.elapsed < within) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Serveur de rattrapage factice : répond [reply] à chaque commit final
/// (null : jamais) ; quand [alive] devient faux (serveur arrêté), toute
/// socket ouverte se ferme en silence.
final class _BackfillServer {
  _BackfillServer({required this.reply, this.alive});

  final String? reply;
  final bool Function()? alive;

  /// Commits finaux reçus (le rattrapage a atteint le serveur).
  int commits = 0;

  final List<_BackfillSocket> _sockets = <_BackfillSocket>[];

  WebSocketClient client() {
    final _BackfillSocket socket = _BackfillSocket(this);
    _sockets.add(socket);
    return socket;
  }

  /// Fin du processus jouée : toute attente en vol se termine (en erreur)
  /// pour que le test puisse libérer ses services ; ce qu'elle écrit
  /// ensuite n'est plus lu (le disque du `terminate` est restauré).
  void endOfProcess() {
    for (final _BackfillSocket s in _sockets) {
      s._messages.addError(const SocketException('process ended'));
    }
  }
}

final class _BackfillSocket extends WebSocketClient {
  _BackfillSocket(this._server);

  final _BackfillServer _server;
  bool _connected = false;
  Timer? _watch;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  bool get _serverUp => _server.alive?.call() ?? true;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    if (!_serverUp) throw const SocketException('Connection refused');
    _connected = true;
    _watch = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_serverUp || !_connected) return;
      // Comme WebSocketClient quand le serveur meurt : la connexion se
      // ferme (onDone), aucune erreur ni `done` sur messageStream ; le
      // rattrapage en vol attend alors son délai (60 s), bien après la fin
      // de l'app.
      _close();
    });
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] != 'input_audio_buffer.commit') return;
    _server.commits++;
    final String? text = _server.reply;
    if (text == null) return;
    Timer(const Duration(milliseconds: 100), () {
      if (!_connected) return;
      _messages.add(
        jsonEncode(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': text,
        }),
      );
    });
  }

  @override
  Future<void> disconnect() async => _close();

  @override
  Future<void> dispose() async => _close();

  void _close() {
    _connected = false;
    _watch?.cancel();
  }
}
