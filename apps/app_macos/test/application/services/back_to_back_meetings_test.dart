import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #16. Réunions à la suite (cas normal), course au redémarrage,
// « Passer » pendant le rattrapage. Temps réel (vrais WAV dans le dossier
// temporaire de test, vérifié), sockets factices, aucun réseau.
//
// Câblage repris de gap_backfill_retry.provider.dart : le rattrapage et sa
// relance lisent le même prédicat « enregistrement » que la production,
// `transcription.isTranscribingStream.value`. Il doit être vrai dès qu'un
// démarrage est demandé (point 2).
//
// API supposée : `WebSocketPcmTranscriber(shouldYield: bool Function())`,
// lu avant chaque morceau ; vrai → la retranscription s'arrête (échec
// réessayable, socket fermée).
void main() {
  setUp(() async {
    final String dir = LiveTranscriptionService.recordingsDir;
    expect(dir, startsWith(Directory.systemTemp.path));
    expect(dir, isNot(contains('/Library/Application Support/')));
    final Directory d = Directory(dir);
    if (d.existsSync()) await d.delete(recursive: true);
    await d.create(recursive: true);
  });

  group('réunion B démarrée pendant la finalisation de A (point 1)', () {
    test(
      'pendant l attente du rattrapage : B démarre aussitôt, l audio non '
      'livré de A devient un repère sur A, rien n est attribué à B',
      () async {
        final FakeVoxServer vox = FakeVoxServer();
        final FakeVoxSocket mic = FakeVoxSocket(vox)..autoReply = false;
        final _Rig rig = _Rig(
          remote: TranscriptionRemoteDataSourceImpl(
            micClient: mic,
            systemClient: FakeVoxSocket(vox),
          ),
        );
        await rig.start();
        final String a = rig.sessionId;
        await rig.speak(0, 30); // phrase de A, jamais acquittée

        unawaited(rig.service.stopTranscription());
        await Future<void>.delayed(const Duration(milliseconds: 500));

        await rig.start().timeout(const Duration(seconds: 5));
        final String b = rig.sessionId;
        expect(b, isNot(a));
        expect(rig.service.isRecording, isTrue);
        expect(rig.markersOf(a), hasLength(1), reason: 'une perte sur A');

        mic.autoReply = true;
        await rig.speak(0, 10);
        await rig.speak(10, 15, voiced: false);
        await Future<void>.delayed(const Duration(seconds: 2));
        final List<TranscriptSegmentEntity> bSegments = rig
            .segments
            .store
            .values
            .where((TranscriptSegmentEntity s) => s.sessionId == b)
            .toList();
        expect(bSegments, isNotEmpty);
        expect(
          bSegments.every((TranscriptSegmentEntity s) => s.timestampMs < 10000),
          isTrue,
          reason: 'heures de B, pas de A',
        );
        expect(rig.markersOf(b), isEmpty);
        await rig.service.stopTranscription();
      },
    );

    test('pendant le rattrapage depuis le WAV : B démarre, le rattrapage de '
        'A cède avant le morceau suivant, ferme sa socket, garde son repère '
        'et sera réessayé', () async {
      final _Rig rig = _Rig(remote: FakeTranscriptionRemoteDataSource());
      // 2 s par morceau : le rattrapage complet (4 morceaux) dépasse les 5 s
      // laissées au démarrage de B.
      rig.backfillServer.answerAfter = const Duration(seconds: 2);
      await rig.start();
      final String a = rig.sessionId;
      await rig.speak(0, 950); // 95 s de WAV
      rig.gap(1000, 91000); // 90 s : plusieurs morceaux de 30 s
      await Future<void>.delayed(const Duration(milliseconds: 200));

      unawaited(rig.service.stopTranscription());
      await rig.until(() => rig.backfillServer.log.contains('done'));

      await rig.start().timeout(const Duration(seconds: 5));
      final DateTime bRecording = DateTime.now();
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(
        rig.backfillServer.appendTimes.where(
          (DateTime t) => t.isAfter(bRecording),
        ),
        isEmpty,
        reason: 'aucun morceau envoyé pendant que B enregistre',
      );
      expect(rig.backfillServer.closedAt, isNotNull);
      expect(
        rig.backfillServer.closedAt!.difference(bRecording),
        lessThanOrEqualTo(const Duration(seconds: 1)),
        reason: 'pas de socket de rattrapage ouverte pendant B',
      );
      expect(rig.markersOf(a), hasLength(1), reason: 'repère gardé');

      await rig.service.stopTranscription();
      await rig.retry.retryPending();
      expect(rig.markersOf(a), isEmpty, reason: 'réessayé puis rattrapé');
    });
  });

  test('point 2 : la relance ne démarre aucun morceau pendant le démarrage '
      'd un enregistrement', () async {
    final _Rig rig = _Rig(remote: FakeTranscriptionRemoteDataSource());
    rig.backfillServer.available = false; // A : serveur de rattrapage absent
    await rig.start();
    await rig.speak(0, 300);
    rig.gap(1000, 20000);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await rig.service.stopTranscription();
    await rig.process.stopServer(); // passe post-session : serveur arrêté

    rig.backfillServer.available = true;
    await rig.start(); // relance le serveur : `ready` avant l'enregistrement
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(
      rig.backfillServer.log,
      isNot(contains('append')),
      reason: 'aucun morceau une fois un démarrage demandé',
    );
    await rig.service.stopTranscription();
  });

  test('point 3 : Passer pendant le rattrapage libère l écran aussitôt ; le '
      'repère reste jusqu à son remplacement', () async {
    final _Rig rig = _Rig(remote: FakeTranscriptionRemoteDataSource());
    rig.backfillServer.answerAfter = const Duration(seconds: 1);
    final List<Duration> remaining = <Duration>[];
    rig.service.finalisingRemainingStream.listen(remaining.add);
    await rig.start();
    final String a = rig.sessionId;
    await rig.speak(0, 950);
    rig.gap(1000, 91000);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    bool stopped = false;
    unawaited(rig.service.stopTranscription().then((_) => stopped = true));
    await rig.until(() => rig.backfillServer.log.contains('append'));
    expect(stopped, isFalse, reason: 'l arrêt attend le rattrapage');
    expect(remaining.last, greaterThan(Duration.zero));

    rig.service.skipFinalising();
    await rig.until(() => stopped, within: const Duration(seconds: 1));
    expect(stopped, isTrue, reason: 'Passer agit aussi pendant le rattrapage');
    expect(remaining.last, Duration.zero);
    expect(rig.markersOf(a), hasLength(1));

    await Future<void>.delayed(const Duration(seconds: 6));
    await rig.retry.retryPending();
    expect(rig.markersOf(a), isEmpty);
  });
}

/// Service réel monté sur des faux ; rattrapage par WebSocketPcmTranscriber
/// sur une socket factice.
final class _Rig {
  _Rig({required this.remote}) {
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

  final TranscriptionRemoteDataSource remote;
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  final InMemoryTranscriptRepository segments = InMemoryTranscriptRepository();
  final _BackfillServer backfillServer = _BackfillServer();
  late final TranscriptionService transcription;
  late final GapBackfillRetry retry;
  late final LiveTranscriptionService service;

  String get sessionId => transcription.currentSessionStream.value!.id;
  int get t0 => transcription
      .currentSessionStream
      .value!
      .createdAt
      .millisecondsSinceEpoch;

  Future<void> start() => service.startTranscription(
    serverCommand: 'uvx',
    serverArgs: const <String>['voxmlx-serve'],
  );

  Future<void> speak(int fromId, int count, {bool voiced = true}) async {
    for (int id = fromId; id < fromId + count; id++) {
      audio.emit(
        chunk(
          AudioSource.input,
          id,
          timestampMs: t0 + id * 100,
          voiced: voiced,
        ),
      );
      if (id % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  /// Perte signalée sur la session courante, en ms depuis son début.
  void gap(int startMs, int endMs) =>
      (remote as FakeTranscriptionRemoteDataSource).emitGap(
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
            s.text.startsWith('Transcription interrompue'),
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

/// Serveur de rattrapage factice : `done` par commit final après
/// [answerAfter] (null : jamais) ; refuse la connexion si pas [available].
final class _BackfillServer {
  bool available = true;
  Duration? answerAfter = const Duration(milliseconds: 200);
  final List<String> log = <String>[];
  final List<DateTime> appendTimes = <DateTime>[];
  DateTime? closedAt;

  WebSocketClient client() => _BackfillSocket(this);
}

final class _BackfillSocket extends WebSocketClient {
  _BackfillSocket(this._server);

  final _BackfillServer _server;
  bool _connected = false;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    if (!_server.available) {
      throw const SocketException('Connection refused');
    }
    _connected = true;
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      _server.log.add('append');
      _server.appendTimes.add(DateTime.now());
    } else if (json['type'] == 'input_audio_buffer.commit') {
      _server.log.add('commit');
      final Duration? delay = _server.answerAfter;
      if (delay == null) return;
      Timer(delay, () {
        if (!_connected) return;
        _server.log.add('done');
        _messages.add(
          jsonEncode(<String, Object>{
            'type': 'response.audio_transcript.done',
            'text': 'Retrouvé.',
          }),
        );
      });
    }
  }

  @override
  Future<void> disconnect() async => _close();

  @override
  Future<void> dispose() async => _close();

  void _close() {
    if (_connected || _server.closedAt == null) {
      _server.closedAt = DateTime.now();
    }
    _connected = false;
  }
}
