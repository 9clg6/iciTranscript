// Full-disk probe: the real LiveTranscriptionService, real WavRecorder, real
// SQLite database (drift) and real repositories, with the app's data folder
// on a small disk image (TMPDIR on the image: under `flutter test` the app's
// data folder is a fresh temporary folder there). Audio capture and the
// process manager are the repo's fakes; the server is a real voxmlx-serve
// on 8017 behind the probe proxy (8018/8019).
//
// Not part of the suite: `flutter test tool/disk_probe.dart` with
//   MODE=meeting|relaunch, AUDIO=<probe audio dir>, OUT=<jsonl>,
//   SECONDS, FREE_AT=<s> (deletes DUMMY), KILL_AT=<s>, DUMMY=<file>,
//   DATA_DIR=<data folder of the killed run> (relaunch).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:core_data/datasources/local/impl/session.local.data_source.impl.dart';
import 'package:core_data/datasources/local/impl/transcript.local.data_source.impl.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/repositories/session.repository.impl.dart';
import 'package:core_data/repositories/transcript.repository.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/launch_repair.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../packages/core_data/tool/probe_proxy.dart';
import '../test/helpers/live_service_fakes.dart'
    show FakeAudioCaptureChannel, FakeProcessManagerChannel;

const String probeUrl = 'ws://127.0.0.1:8018/v1/realtime';
const String serverUrl = 'ws://127.0.0.1:8017/v1/realtime';

Future<int?> dfFree(String path) async {
  final ProcessResult r = await Process.run('/bin/df', <String>['-k', path]);
  final List<String> cols = (r.stdout as String)
      .trim()
      .split('\n')
      .last
      .trim()
      .split(RegExp(r'\s+'));
  final int? kb = cols.length > 3 ? int.tryParse(cols[3]) : null;
  return kb == null ? null : kb * 1024;
}

void main() {
  test('disk probe', () async {
    final Map<String, String> env = Platform.environment;
    final String mode = env['MODE']!;
    initProbeLog(env['OUT']!, DateTime.now().millisecondsSinceEpoch);
    final String dataDir = env['DATA_DIR'] ?? appDataDirectory();
    final String recordingsDir = mode == 'relaunch'
        ? '$dataDir/recordings'
        : LiveTranscriptionService.recordingsDir;
    Directory(recordingsDir).createSync(recursive: true);
    final String dbPath = '$dataDir/ici_transcript.sqlite';
    log('start', <String, Object?>{
      'mode': mode,
      'dataDir': dataDir,
      'recordingsDir': recordingsDir,
      'pid': pid,
    });

    // 2. freeBytesAt vs df -k on the same volume.
    final int? viaApp = await RecordingStorage.freeBytesAt(recordingsDir);
    final int? viaDf = await dfFree(recordingsDir);
    log('free_check', <String, Object?>{'freeBytesAt': viaApp, 'df_k': viaDf});

    // Fill the volume from here, after the test was compiled (the Flutter
    // tooling also writes under TMPDIR): a real file, not a sparse one.
    final int? leaveMb = int.tryParse(env['FILL_LEAVE_MB'] ?? '');
    if (leaveMb != null) {
      final RandomAccessFile f = File(
        env['DUMMY']!,
      ).openSync(mode: FileMode.write);
      final Uint8List mb = Uint8List(1 << 20);
      for (int i = 0; i < mb.length; i++) {
        mb[i] = (i * 2654435761) & 0xFF;
      }
      while (((await dfFree(recordingsDir)) ?? 0) > (leaveMb + 1) << 20) {
        f.writeFromSync(mb);
        f.flushSync();
      }
      f.closeSync();
      log('dummy_filled', <String, Object?>{
        'free_bytes': await dfFree(recordingsDir),
        'freeBytesAt': await RecordingStorage.freeBytesAt(recordingsDir),
      });
    }
    final AppDatabase db = AppDatabase(NativeDatabase(File(dbPath)));
    final SessionRepositoryImpl sessions = SessionRepositoryImpl(
      sessionLocalDataSource: SessionLocalDataSourceImpl(
        sessionDao: SessionDao(db),
      ),
    );
    final TranscriptRepositoryImpl transcripts = TranscriptRepositoryImpl(
      transcriptLocalDataSource: TranscriptLocalDataSourceImpl(
        transcriptSegmentDao: TranscriptSegmentDao(db),
      ),
    );
    final TranscriptionService transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: transcripts,
      ),
    );
    bool isRecording() => transcription.isTranscribingStream.value;
    final StreamController<ServerState> states =
        StreamController<ServerState>.broadcast();
    final GapBackfillRetry retry = GapBackfillRetry(
      backfill: GapBackfillService(
        transcriber: WebSocketPcmTranscriber(
          url: serverUrl,
          shouldYield: isRecording,
        ),
        transcripts: transcripts,
        isRecording: isRecording,
      ),
      serverStates: states.stream,
      isRecording: isRecording,
      recordingsDirectory: recordingsDir,
    );

    Future<void> dump(String step) async {
      final List<Map<String, Object?>> list = <Map<String, Object?>>[];
      for (final SessionEntity s in await sessions.getAll()) {
        for (final TranscriptSegmentEntity g
            in await transcripts.getBySessionId(s.id)) {
          list.add(<String, Object?>{
            'session': s.id,
            'status': s.status.name,
            'src': g.source == AudioSource.input ? 'mic' : 'sys',
            't': g.timestampMs / 1000,
            'id': g.id,
            'text': g.text,
          });
        }
      }
      log('segments', <String, Object?>{'step': step, 'list': list});
    }

    if (mode == 'relaunch') {
      await dump('before_repair');
      await LaunchRepair(
        sessions: sessions,
        transcripts: transcripts,
        recordingsDir: recordingsDir,
      ).run();
      await dump('after_repair');
      for (final SessionEntity s in await sessions.getAll()) {
        await retry.enqueue(s.id);
      }
      await retry.retryPending();
      final Stopwatch sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < int.parse(env['WAIT'] ?? '600')) {
        final List<TranscriptSegmentEntity> all = <TranscriptSegmentEntity>[
          for (final SessionEntity s in await sessions.getAll())
            ...await transcripts.getBySessionId(s.id),
        ];
        if (!all.any(
          (TranscriptSegmentEntity g) =>
              g.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
        )) {
          break;
        }
        await retry.retryPending();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await dump('after_backfill');
      await retry.dispose();
      await db.close();
      await closeProbeLog();
      return;
    }

    final Proxy micProxy = Proxy('mic', 8018);
    final Proxy sysProxy = Proxy('sys', 8019);
    await micProxy.listen();
    await sysProxy.listen();
    WebSocketClient client(String src, int port) => WebSocketClient(
      connectChannel: (Uri uri) {
        log('connect', <String, Object?>{'src': src});
        return WebSocketChannel.connect(uri.replace(port: port));
      },
    );
    final FakeAudioCaptureChannel capture = FakeAudioCaptureChannel();
    final LiveTranscriptionService service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(
        channel: FakeProcessManagerChannel(),
      ),
      audioCaptureChannel: capture,
      transcriptionRemoteDataSource: TranscriptionRemoteDataSourceImpl(
        micClient: client('mic', 8018),
        systemClient: client('sys', 8019),
      ),
      transcriptionService: transcription,
      gapBackfillRetry: retry,
      freeBytes: () => RecordingStorage.freeBytesAt(recordingsDir),
    );
    service.storageStream.listen(
      (RecordingStorage s) => log('storage', <String, Object?>{
        'level': s.level.name,
        'time_left_s': s.recordingTimeLeft?.inSeconds,
        'audio_copy_failing': s.audioCopyFailing,
        'unsaved_lines': s.unsavedLines,
      }),
    );
    Map<String, TranscriptSegmentEntity> onScreen =
        <String, TranscriptSegmentEntity>{};
    final Map<String, String> seen = <String, String>{};
    transcription.segmentsStream.listen((List<TranscriptSegmentEntity> list) {
      final Map<String, TranscriptSegmentEntity> now =
          <String, TranscriptSegmentEntity>{
            for (final TranscriptSegmentEntity s in list) s.id: s,
          };
      for (final TranscriptSegmentEntity g in onScreen.values) {
        if (!now.containsKey(g.id)) {
          log('segment_removed', <String, Object?>{
            'src': g.source == AudioSource.input ? 'mic' : 'sys',
            'id': g.id,
            'text': g.text,
          });
        }
      }
      onScreen = now;
      for (final TranscriptSegmentEntity s in list) {
        if (seen[s.id] == s.text) continue;
        seen[s.id] = s.text;
        log('segment', <String, Object?>{
          'session': s.sessionId,
          'src': s.source == AudioSource.input ? 'mic' : 'sys',
          'ts': s.timestampMs / 1000,
          'id': s.id,
          'text': s.text,
        });
      }
    });
    final Timer freeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async =>
          log('free', <String, Object?>{'bytes': await dfFree(recordingsDir)}),
    );
    final double secs = double.parse(env['SECONDS'] ?? '600');
    final double? freeAt = double.tryParse(env['FREE_AT'] ?? '');
    final double? killAt = double.tryParse(env['KILL_AT'] ?? '');
    if (freeAt != null) {
      Timer(Duration(milliseconds: (freeAt * 1000).round()), () {
        File(env['DUMMY']!).deleteSync();
        log('dummy_deleted');
      });
    }
    if (killAt != null) {
      Timer(Duration(milliseconds: (killAt * 1000).round()), () async {
        await dump('before_kill');
        log('kill_self');
        Process.killPid(pid, ProcessSignal.sigkill);
      });
    }

    log('meeting_start');
    await service.startTranscription(
      outputEnabled: true,
      serverCommand: 'voxmlx-serve',
      webSocketUrl: probeUrl,
    );
    final Uint8List mic = readPcm('${env['AUDIO']}/paused/mic.wav');
    final Uint8List sys = readPcm('${env['AUDIO']}/paused/sys.wav');
    final int t0 = DateTime.now().millisecondsSinceEpoch;
    log('feed_start', <String, Object?>{'seconds': secs});
    for (int i = 0; i < (secs * 10).round(); i++) {
      final int due = t0 + i * 100;
      final int wait = due - DateTime.now().millisecondsSinceEpoch;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      final int at = i * 3200;
      for (final (AudioSource src, Uint8List pcm) in <(AudioSource, Uint8List)>[
        (AudioSource.input, mic),
        (AudioSource.output, sys),
      ]) {
        if (at + 3200 > pcm.length) continue;
        capture.emit(
          AudioChunk(
            source: src,
            data: Uint8List.sublistView(pcm, at, at + 3200),
            timestampMs: due,
          ),
        );
      }
    }
    log('meeting_stop');
    final Stopwatch sw = Stopwatch()..start();
    await service.stopTranscription();
    log('meeting_stopped', <String, Object?>{
      'took_s': sw.elapsedMilliseconds / 1000,
    });
    freeTimer.cancel();
    await dump('final');
    await micProxy.close();
    await sysProxy.close();
    await db.close();
    await closeProbeLog();
  }, timeout: Timeout.none);
}
