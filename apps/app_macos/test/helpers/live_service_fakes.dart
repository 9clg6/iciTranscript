import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:fake_async/fake_async.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';
import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

// Faux sans réseau, sans processus, sans disque, pour piloter
// [LiveTranscriptionService] sous fake_async. Les canaux plateforme sont
// étendus (`extends`) pour rester compilables si leur API grandit ; les
// services `final` (ProcessManagerService, TranscriptionService) sont les
// vrais, montés sur ces faux.

/// Serveur ML factice : démarrages comptés et datés, crash à la demande.
final class FakeProcessManagerChannel extends ProcessManagerChannel {
  FakeProcessManagerChannel({this.now});

  final Duration Function()? now;

  /// Les démarrages suivants échouent (serveur qui ne revient pas).
  bool failStarts = false;

  /// Durée d'un démarrage (chargement du modèle).
  Duration startDuration = Duration.zero;

  /// Appelé quand un démarrage réussit.
  void Function()? onReady;

  final List<({String command, List<String> args, String? readyPattern})>
  starts = <({String command, List<String> args, String? readyPattern})>[];
  final List<Duration> startTimes = <Duration>[];

  bool _running = false;
  ServerState _state = ServerState.stopped;
  final StreamController<ServerState> _states =
      StreamController<ServerState>.broadcast();

  void _set(ServerState state) {
    _state = state;
    _states.add(state);
  }

  /// Le processus meurt (code de sortie non nul).
  void crash() {
    _running = false;
    _set(ServerState.error);
  }

  @override
  Stream<ServerState> get stateStream => _states.stream;

  @override
  Stream<String> get logsStream => const Stream<String>.empty();

  @override
  Future<void> startServer({
    required String command,
    List<String> args = const <String>[],
    String? readyPattern,
  }) async {
    starts.add((command: command, args: args, readyPattern: readyPattern));
    final Duration? at = now?.call();
    if (at != null) startTimes.add(at);
    _set(ServerState.starting);
    if (startDuration > Duration.zero) {
      await Future<void>.delayed(startDuration);
    }
    if (failStarts) {
      _set(ServerState.error);
      throw StateError('Le serveur ML s\'est arrêté avant d\'être prêt (1)');
    }
    _running = true;
    _set(ServerState.ready);
    onReady?.call();
  }

  @override
  Future<void> stopServer() async {
    _running = false;
    _set(ServerState.stopped);
  }

  @override
  Future<bool> isServerRunning() async => _running;

  @override
  Future<ServerState> getServerState() async => _state;

  @override
  Future<bool> checkUvxAvailable() async => true;

  @override
  Future<bool> installUv() async => true;

  @override
  Future<void> dispose() async => _states.close();
}

/// Capture audio factice : le test pousse les chunks.
final class FakeAudioCaptureChannel extends AudioCaptureChannel {
  final StreamController<AudioChunk> _audio =
      StreamController<AudioChunk>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  /// Journal ordonné des démarrages et arrêts ; partageable avec d'autres
  /// faux pour vérifier un ordre entre eux.
  List<String> log = <String>[];

  /// Micro demandé à chaque [startCapture] (null : celui du système).
  final List<String?> inputDeviceIds = <String?>[];

  /// Levée (une fois) par le prochain [startCapture], ex. permission micro.
  Object? startError;

  void emit(AudioChunk chunk) => _audio.add(chunk);

  @override
  Stream<AudioChunk> get audioStream => _audio.stream;

  @override
  Stream<Map<String, String>> get statusStream =>
      const Stream<Map<String, String>>.empty();

  @override
  Future<void> startCapture({
    String? inputDeviceId,
    bool outputEnabled = false,
  }) async {
    startCalls++;
    inputDeviceIds.add(inputDeviceId);
    log.add('capture.start(output: $outputEnabled)');
    final Object? error = startError;
    startError = null;
    if (error != null) throw error;
  }

  @override
  Future<void> stopCapture() async {
    stopCalls++;
    log.add('capture.stop');
  }

  @override
  Future<List<AudioDeviceEntity>> listDevices() async =>
      const <AudioDeviceEntity>[];

  @override
  Future<bool> isSystemAudioAvailable() async => true;

  @override
  Future<Map<String, String>> checkPermissions() async => <String, String>{
    'mic': 'authorized',
    'screenRecording': 'authorized',
  };

  @override
  Future<void> openSystemSettings(String pane) async {}

  @override
  Future<void> dispose() async => _audio.close();
}

/// Source distante factice : le test joue le rôle du serveur.
final class FakeTranscriptionRemoteDataSource
    implements TranscriptionRemoteDataSource {
  final List<AudioChunk> sentAudio = <AudioChunk>[];
  int connectCalls = 0;

  /// URL reçue à chaque connexion.
  final List<String> connectedUrls = <String>[];

  final StreamController<TranscriptEventRemoteModel> _mic =
      StreamController<TranscriptEventRemoteModel>.broadcast();
  final StreamController<TranscriptEventRemoteModel> _system =
      StreamController<TranscriptEventRemoteModel>.broadcast();
  final StreamController<AudioGap> _gaps =
      StreamController<AudioGap>.broadcast();
  final StreamController<domain.ConnectionState> _states =
      StreamController<domain.ConnectionState>.broadcast();
  final Expando<UtteranceWindow> _windows = Expando<UtteranceWindow>();

  StreamController<TranscriptEventRemoteModel> _of(AudioSource source) =>
      source == AudioSource.input ? _mic : _system;

  void emitDelta(AudioSource source, String delta) => _of(source).add(
    TranscriptEventRemoteModel(
      type: 'response.audio_transcript.delta',
      delta: delta,
    ),
  );

  /// Événement interne de la source distante (ex. phrase perdue).
  void emitControl(AudioSource source, String type) =>
      _of(source).add(TranscriptEventRemoteModel(type: type));

  void emitDone(AudioSource source, String text, {UtteranceWindow? window}) {
    final TranscriptEventRemoteModel event = TranscriptEventRemoteModel(
      type: 'response.audio_transcript.done',
      text: text,
    );
    if (window != null) _windows[event] = window;
    _of(source).add(event);
  }

  void emitGap(AudioGap gap) => _gaps.add(gap);

  void emitConnectionState(domain.ConnectionState state) => _states.add(state);

  @override
  Future<void> connect({
    String url = 'ws://localhost:8000/v1/realtime',
    bool systemAudioEnabled = true,
  }) async {
    connectCalls++;
    connectedUrls.add(url);
    _states.add(domain.ConnectionState.connected);
  }

  @override
  void sendAudio(AudioChunk chunk) => sentAudio.add(chunk);

  @override
  Stream<TranscriptEventRemoteModel> get transcriptionStream => _mic.stream;

  @override
  Stream<TranscriptEventRemoteModel> get systemTranscriptionStream =>
      _system.stream;

  @override
  Stream<AudioGap> get audioGaps => _gaps.stream;

  /// Sources dont une phrase attend encore sa fin (l'arrêt les attend).
  Set<AudioSource> active = <AudioSource>{};

  @override
  Set<AudioSource> get activeSources => active;

  @override
  UtteranceWindow? windowOf(TranscriptEventRemoteModel event) =>
      _windows[event];

  /// Pertes rendues à la déconnexion (comme la vraie source : ce qui n'a
  /// pas eu son `done` à l'arrêt devient une perte signalée).
  List<AudioGap> gapsOnDisconnect = <AudioGap>[];

  @override
  Future<void> disconnect() async {
    for (final AudioGap gap in gapsOnDisconnect) {
      _gaps.add(gap);
    }
    gapsOnDisconnect = <AudioGap>[];
    _states.add(domain.ConnectionState.disconnected);
  }

  /// Sources visées par chaque commit final (null : toutes).
  final List<Set<AudioSource>?> finalCommitSources = <Set<AudioSource>?>[];

  @override
  Set<AudioSource> sendCommit({
    bool isFinal = false,
    Set<AudioSource>? sources,
  }) {
    if (isFinal) finalCommitSources.add(sources);
    return <AudioSource>{};
  }

  @override
  Stream<domain.ConnectionState> get connectionState => _states.stream;
}

final class InMemorySessionRepository implements SessionRepository {
  final Map<String, SessionEntity> store = <String, SessionEntity>{};

  @override
  Future<List<SessionEntity>> getAll() async => store.values.toList();

  @override
  Future<SessionEntity?> getById(String id) async => store[id];

  @override
  Future<SessionEntity> create(SessionEntity session) async =>
      store[session.id] = session;

  @override
  Future<SessionEntity> update(SessionEntity session) async =>
      store[session.id] = session;

  @override
  Future<void> delete(String id) async => store.remove(id);

  @override
  Stream<List<SessionEntity>> watchAll() =>
      Stream<List<SessionEntity>>.value(store.values.toList());
}

/// Dépôt en mémoire au contrat du port : `save` remplace un segment de même
/// id (en gardant sa place), `deleteById` le retire.
class InMemoryTranscriptRepository implements TranscriptRepository {
  final Map<String, TranscriptSegmentEntity> store =
      <String, TranscriptSegmentEntity>{};

  /// Segments sauvés, dans l'ordre de première écriture.
  List<TranscriptSegmentEntity> of(AudioSource source) => store.values
      .where((TranscriptSegmentEntity s) => s.source == source)
      .toList();

  @override
  Future<List<TranscriptSegmentEntity>> getBySessionId(
    String sessionId,
  ) async => store.values
      .where((TranscriptSegmentEntity s) => s.sessionId == sessionId)
      .toList();

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async =>
      store[segment.id] = segment;

  @override
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> segments,
  ) async {
    for (final TranscriptSegmentEntity s in segments) {
      store[s.id] = s;
    }
    return segments;
  }

  @override
  Future<void> deleteById(String id) async => store.remove(id);

  @override
  Future<void> deleteBySessionId(String sessionId) async => store.removeWhere(
    (String _, TranscriptSegmentEntity s) => s.sessionId == sessionId,
  );
}

/// Enregistreur WAV sans disque : compte ce qu'il reçoit, ne le garde pas.
final class FakeWavRecorder extends WavRecorder {
  String? path;
  int bytes = 0;
  int chunks = 0;
  bool closed = false;

  @override
  bool get isOpen => path != null && !closed;

  @override
  Future<void> open(String path) async => this.path = path;

  @override
  Future<void> append(Uint8List pcm) async {
    if (!isOpen) return;
    bytes += pcm.length;
    chunks++;
  }

  @override
  Future<void> close() async => closed = true;
}

/// Monte le vrai [LiveTranscriptionService] sur les faux ci-dessus.
final class LiveServiceHarness {
  LiveServiceHarness(
    this.async, {
    TranscriptionRemoteDataSource? remote,
    InMemoryTranscriptRepository? segments,
    WavRecorder Function()? createWavRecorder,
  }) : process = FakeProcessManagerChannel(now: () => async.elapsed),
       remote = remote ?? FakeTranscriptionRemoteDataSource(),
       segments = segments ?? InMemoryTranscriptRepository() {
    transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: this.segments,
      ),
    );
    service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(channel: process),
      audioCaptureChannel: audio,
      transcriptionRemoteDataSource: this.remote,
      transcriptionService: transcription,
      // Un vrai enregistreur (disque factice) si le test en donne un.
      createWavRecorder:
          createWavRecorder ??
          () {
            final FakeWavRecorder recorder = FakeWavRecorder();
            recorders.add(recorder);
            return recorder;
          },
    );
  }

  final FakeAsync async;
  final FakeProcessManagerChannel process;
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final TranscriptionRemoteDataSource remote;
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  final InMemoryTranscriptRepository segments;
  final List<FakeWavRecorder> recorders = <FakeWavRecorder>[];
  late final TranscriptionService transcription;
  late final LiveTranscriptionService service;

  FakeTranscriptionRemoteDataSource get fakeRemote =>
      remote as FakeTranscriptionRemoteDataSource;

  static const String command = 'uvx';
  static const List<String> args = <String>['voxmlx-serve', '--model', 'm'];

  SessionEntity get session => transcription.currentSessionStream.value!;

  /// Début de session en ms epoch, l'horloge des chunks de capture.
  int get t0 => session.createdAt.millisecondsSinceEpoch;

  void start({bool outputEnabled = true, bool enablePostProcessing = false}) {
    unawaited(
      service.startTranscription(
        outputEnabled: outputEnabled,
        serverCommand: command,
        serverArgs: args,
        enablePostProcessing: enablePostProcessing,
      ),
    );
    async.elapse(const Duration(seconds: 1));
  }

  void stop() {
    unawaited(service.stopTranscription());
    async.elapse(const Duration(seconds: 10));
  }
}

/// Chunk PCM16 de 100 ms portant son numéro [id] dans ses deux premiers
/// échantillons. Voisé : amplitude 1200, au-dessus du seuil de parole.
AudioChunk chunk(
  AudioSource source,
  int id, {
  required int timestampMs,
  bool voiced = true,
}) {
  final Uint8List data = Uint8List(3200);
  final ByteData samples = ByteData.sublistView(data);
  if (voiced) {
    for (int offset = 4; offset < data.length; offset += 2) {
      samples.setInt16(offset, 1200, Endian.little);
    }
  }
  samples.setInt16(0, id & 0x7FFF, Endian.little);
  samples.setInt16(2, id >> 15, Endian.little);
  return AudioChunk(source: source, data: data, timestampMs: timestampMs);
}

/// Serveur voxmlx factice partagé par les deux sockets.
final class FakeVoxServer {
  FakeVoxServer({this.now, this.speed});

  bool up = true;

  /// Horloge du test, requise si [speed] est donné.
  final Duration Function()? now;

  /// Serveur séquentiel (comme le vrai, sonde 2026-11-22) : il traite
  /// l'audio de toutes les sockets dans une seule file, [speed] fois plus
  /// vite que le temps réel. Null : réponse en 400 ms, sans file. Peut
  /// changer en cours de test (serveur durablement ralenti puis rétabli).
  double? speed;

  /// Retard ajouté à chaque réponse (proxy « Dlag » des sondes).
  Duration lag = Duration.zero;
  Duration _busyUntil = Duration.zero;

  /// Met [audio] dans la file ; rend l'instant où il aura été traité.
  Duration process(Duration audio) {
    final Duration t = now!();
    final Duration start = _busyUntil > t ? _busyUntil : t;
    _busyUntil = start + audio * (1 / speed!);
    return _busyUntil;
  }

  Duration get busyUntil => _busyUntil;
}

/// Socket factice qui joue voxmlx : relit le numéro de chaque chunk reçu
/// (sans garder le payload) et, si [autoReply], répond à chaque commit final
/// par un delta puis un `done` 400 ms plus tard, tant que la connexion qui
/// l'a reçu est vivante. Sinon le test répond lui-même avec [emit].
final class FakeVoxSocket extends WebSocketClient {
  FakeVoxSocket(this.server);

  final FakeVoxServer server;

  /// Refus de connexion propre à cette socket (coupure réseau ciblée).
  bool refusing = false;

  /// La poignée de main reste sans réponse.
  bool hanging = false;

  /// Répond seul aux commits finaux.
  bool autoReply = true;

  /// Texte du `done` de la n-ième phrase.
  String Function(int n) reply = (int n) => 'Phrase numéro $n.';

  bool _connected = false;
  int _generation = 0;
  int _phrases = 0;
  int connectCalls = 0;

  /// Phrases finales (`done`) réellement envoyées au client.
  int doneSent = 0;

  /// Numéros des chunks reçus, toutes connexions confondues, dans l'ordre.
  final List<int> receivedIds = <int>[];

  /// Numéros reçus, connexion par connexion.
  final List<List<int>> connections = <List<int>>[];

  /// Chunks transcrits : reçus avant un commit final dont le `done` est
  /// parti sur la même connexion.
  final Set<int> transcribedIds = <int>{};

  /// Chunks transcrits deux fois (doublon dans la transcription).
  final List<int> transcribedTwice = <int>[];
  List<int> _sinceCommit = <int>[];

  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    connectCalls++;
    // Poignée de main qui n'aboutit jamais (proxy ralenti, sonde 10) : seule
    // la borne du client y met fin.
    if (hanging) return Completer<void>().future;
    if (!server.up || refusing) {
      throw const SocketException('Connection refused');
    }
    _connected = true;
    _generation++;
    _sinceCommit = <int>[];
    connections.add(<int>[]);
  }

  void drop() {
    _connected = false;
    _generation++;
  }

  /// Le serveur envoie un événement (mode sans [autoReply]).
  void emit(Map<String, Object> event) {
    if (event['type'] == 'response.audio_transcript.done') doneSent++;
    _messages.add(jsonEncode(event));
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      final ByteData s = ByteData.sublistView(
        base64Decode((json['audio'] as String).substring(0, 8)),
      );
      final int id =
          s.getInt16(0, Endian.little) + (s.getInt16(2, Endian.little) << 15);
      receivedIds.add(id);
      connections.last.add(id);
      _sinceCommit.add(id);
      if (server.speed != null) {
        final Duration doneAt = server.process(
          const Duration(milliseconds: 100),
        );
        // Le modèle émet du texte au fil du traitement : signe de vie.
        if (autoReply && _sinceCommit.length % 20 == 0) {
          final int generation = _generation;
          Timer(doneAt - server.now!(), () {
            if (!_connected || generation != _generation) return;
            _messages.add(
              jsonEncode(<String, Object>{
                'type': 'response.audio_transcript.delta',
                'delta': '… ',
              }),
            );
          });
        }
      }
    } else if (json['type'] == 'input_audio_buffer.commit' &&
        json['final'] == true) {
      final List<int> utterance = _sinceCommit;
      _sinceCommit = <int>[];
      if (!autoReply) return;
      final int generation = _generation;
      final int n = ++_phrases;
      final Duration delay =
          (server.speed == null
              ? const Duration(milliseconds: 400)
              : server.busyUntil +
                    const Duration(milliseconds: 400) -
                    server.now!()) +
          server.lag;
      Timer(delay, () {
        if (!_connected || generation != _generation) return;
        for (final int id in utterance) {
          if (!transcribedIds.add(id)) transcribedTwice.add(id);
        }
        _messages.add(
          jsonEncode(<String, Object>{
            'type': 'response.audio_transcript.delta',
            'delta': 'phrase $n',
          }),
        );
        doneSent++;
        _messages.add(
          jsonEncode(<String, Object>{
            'type': 'response.audio_transcript.done',
            'text': reply(n),
          }),
        );
      });
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _generation++;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _messages.close();
  }
}
