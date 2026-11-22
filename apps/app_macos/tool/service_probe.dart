// Drives the real LiveTranscriptionService (real data source, real
// WebSocketClient, real WavRecorder, real GapBackfillRetry/Service and
// WebSocketPcmTranscriber) against a real voxmlx-serve through the probe
// proxy. Only audio capture and the process manager are the repo's fakes.
// Sessions and segments are written to a JSON file on every change, so a
// killed run leaves its state on disk like the app's database would.
//
// Not part of the suite: `flutter test tool/service_probe.dart` with
//   MODE=b2b|yield|kill|relaunch|lang, AUDIO=<probe audio dir>,
//   STATE=<state dir>, OUT=<run.jsonl>.
// See tool/server_probe/README.md at the repository root.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../packages/core_data/tool/probe_proxy.dart';
import '../test/helpers/live_service_fakes.dart'
    show FakeAudioCaptureChannel, FakeProcessManagerChannel;

/// Sessions + segments kept in one JSON file, rewritten on every change.
final class FileStore implements SessionRepository, TranscriptRepository {
  FileStore(this.path) {
    final File f = File(path);
    if (!f.existsSync()) return;
    final Map<String, dynamic> j =
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final dynamic s in j['sessions'] as List<dynamic>) {
      final Map<String, dynamic> m = s as Map<String, dynamic>;
      sessions[m['id'] as String] = SessionEntity(
        id: m['id'] as String,
        title: m['title'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        durationSeconds: m['durationSeconds'] as int?,
        status: SessionStatus.values.byName(m['status'] as String),
      );
    }
    for (final dynamic s in j['segments'] as List<dynamic>) {
      final Map<String, dynamic> m = s as Map<String, dynamic>;
      segments[m['id'] as String] = TranscriptSegmentEntity(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        source: AudioSource.values.byName(m['source'] as String),
        text: m['text'] as String,
        timestampMs: m['timestampMs'] as int,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );
    }
  }

  final String path;
  final Map<String, SessionEntity> sessions = <String, SessionEntity>{};
  final Map<String, TranscriptSegmentEntity> segments =
      <String, TranscriptSegmentEntity>{};

  void _flush() {
    final File tmp = File('$path.tmp')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'sessions': <Map<String, Object?>>[
            for (final SessionEntity s in sessions.values)
              <String, Object?>{
                'id': s.id,
                'title': s.title,
                'createdAt': s.createdAt.toIso8601String(),
                'updatedAt': s.updatedAt.toIso8601String(),
                'durationSeconds': s.durationSeconds,
                'status': s.status.name,
              },
          ],
          'segments': <Map<String, Object?>>[
            for (final TranscriptSegmentEntity s in segments.values)
              <String, Object?>{
                'id': s.id,
                'sessionId': s.sessionId,
                'source': s.source.name,
                'text': s.text,
                'timestampMs': s.timestampMs,
                'createdAt': s.createdAt.toIso8601String(),
              },
          ],
        }),
        flush: true,
      );
    tmp.renameSync(path);
  }

  // SessionRepository
  @override
  Future<List<SessionEntity>> getAll() async => sessions.values.toList();
  @override
  Future<SessionEntity?> getById(String id) async => sessions[id];
  @override
  Future<SessionEntity> create(SessionEntity s) async {
    sessions[s.id] = s;
    _flush();
    return s;
  }

  @override
  Future<SessionEntity> update(SessionEntity s) => create(s);
  @override
  Future<void> delete(String id) async {
    sessions.remove(id);
    _flush();
  }

  @override
  Stream<List<SessionEntity>> watchAll() =>
      Stream<List<SessionEntity>>.value(sessions.values.toList());

  // TranscriptRepository
  @override
  Future<List<TranscriptSegmentEntity>> getBySessionId(String id) async =>
      segments.values
          .where((TranscriptSegmentEntity s) => s.sessionId == id)
          .toList()
        ..sort(
          (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
              a.timestampMs.compareTo(b.timestampMs),
        );
  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity s) async {
    segments[s.id] = s;
    _flush();
    return s;
  }

  @override
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> list,
  ) async => <TranscriptSegmentEntity>[for (final s in list) await save(s)];
  @override
  Future<void> deleteById(String id) async {
    segments.remove(id);
    _flush();
  }

  @override
  Future<void> deleteBySessionId(String id) async {
    segments.removeWhere((_, TranscriptSegmentEntity s) => s.sessionId == id);
    _flush();
  }
}

/// Logs every transcribe call (start, end, outcome) of the real transcriber.
final class TimedTranscriber implements PcmTranscriber {
  TimedTranscriber(this.inner, {this.onStart});
  final PcmTranscriber inner;
  final void Function()? onStart;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    onStart?.call();
    log('transcribe_start', <String, Object?>{
      'ms': pcm.length ~/ 32,
      'pieces_ms': <List<int>>[
        for (final ({int start, int end}) p
            in WebSocketPcmTranscriber.splitAtSilences(pcm))
          <int>[p.start ~/ 32, p.end ~/ 32],
      ],
    });
    try {
      final List<({int offsetMs, String text})> r = await inner.transcribe(pcm);
      log('transcribe_end', <String, Object?>{'pieces': r.length});
      return r;
    } catch (e) {
      log('transcribe_error', <String, Object?>{'err': '$e'});
      rethrow;
    }
  }
}

const String probeUrl = 'ws://127.0.0.1:8018/v1/realtime';
const String serverUrl = 'ws://127.0.0.1:8017/v1/realtime';

void main() {
  test('service probe', () async {
    final Map<String, String> env = Platform.environment;
    final String mode = env['MODE']!;
    final String audio = env['AUDIO']!;
    final String stateDir = env['STATE']!;
    Directory(stateDir).createSync(recursive: true);
    initProbeLog(env['OUT']!, DateTime.now().millisecondsSinceEpoch);
    double now() =>
        (DateTime.now().millisecondsSinceEpoch - probeEpoch0) / 1000;
    log('start', <String, Object?>{
      'mode': mode,
      'recordingsDir': LiveTranscriptionService.recordingsDir,
      'pid': pid,
    });

    final FileStore store = FileStore('$stateDir/state.json');
    final TranscriptionService transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: store),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: store),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: store,
      ),
    );
    bool isRecording() => transcription.isTranscribingStream.value;
    final StreamController<ServerState> serverStates =
        StreamController<ServerState>.broadcast();

    String recordingsDir = LiveTranscriptionService.recordingsDir;
    if (mode == 'langcheck') {
      // False positives of the language check: reference sentences of both
      // corpora, and the server's real `done` texts from fault-free runs
      // (FILES, comma-separated JSONL).
      bool flagged(String t) {
        final String n = TranscriptTextNormalizer.normalize(t);
        return TranscriptTextNormalizer.isForeignScript(n) ||
            TranscriptTextNormalizer.isUnexpectedLanguage(n);
      }

      for (final String corpus in <String>['live', 'live60']) {
        final Map<String, dynamic> sched =
            jsonDecode(File('$audio/$corpus/schedule.json').readAsStringSync())
                as Map<String, dynamic>;
        final List<String> texts = <String>[
          for (final dynamic src in sched.values)
            for (final dynamic x in src as List<dynamic>)
              (x as Map<String, dynamic>)['text'] as String,
        ];
        final List<String> hits = texts.where(flagged).toList();
        log('langcheck', <String, Object?>{
          'set': 'reference:$corpus',
          'n': texts.length,
          'flagged': hits.length,
          'examples': hits.take(5).toList(),
        });
      }
      for (final String f in (env['FILES'] ?? '').split(',')) {
        if (f.isEmpty) continue;
        final List<String> texts = <String>[
          for (final String l in File(f).readAsLinesSync())
            if ((jsonDecode(l) as Map<String, dynamic>)['ev'] == 'done')
              (jsonDecode(l) as Map<String, dynamic>)['text'] as String,
        ].where((String t) => t.trim().isNotEmpty).toList();
        final List<String> hits = texts.where(flagged).toList();
        log('langcheck', <String, Object?>{
          'set': 'server:$f',
          'n': texts.length,
          'flagged': hits.length,
          'examples': hits.take(8).toList(),
        });
      }
      await closeProbeLog();
      return;
    }

    if (mode == 'relaunch') {
      recordingsDir =
          (jsonDecode(File('$stateDir/run_info.json').readAsStringSync())
                  as Map<String, dynamic>)['recordingsDir']
              as String;
    } else {
      File('$stateDir/run_info.json').writeAsStringSync(
        jsonEncode(<String, Object?>{'recordingsDir': recordingsDir}),
      );
    }
    final GapBackfillService backfill = GapBackfillService(
      transcriber: TimedTranscriber(
        WebSocketPcmTranscriber(url: serverUrl, shouldYield: isRecording),
        onStart: () => log('plan', <String, Object?>{
          'gaps': <Map<String, Object?>>[
            for (final SessionEntity se in store.sessions.values)
              for (final BackfillGap g in GapBackfillService.plan(
                store.segments.values
                    .where((TranscriptSegmentEntity x) => x.sessionId == se.id)
                    .toList(),
              ))
                <String, Object?>{
                  'session': se.id,
                  'marker': g.markerId,
                  'src': g.source.name,
                  'start_s': g.startMs / 1000,
                  'end_s': g.endMs / 1000,
                  'replaced': g.replacedIds,
                },
          ],
        }),
      ),
      transcripts: store,
      isRecording: isRecording,
    );
    final GapBackfillRetry retry = GapBackfillRetry(
      backfill: backfill,
      serverStates: serverStates.stream,
      isRecording: isRecording,
      recordingsDirectory: recordingsDir,
    );
    final File pendingFile = File('$recordingsDir/.backfill_pending.json');
    void snap(String step) => log('snapshot', <String, Object?>{
      'step': step,
      'pending': pendingFile.existsSync()
          ? pendingFile.readAsStringSync()
          : null,
      'sessions': <String, String>{
        for (final SessionEntity s in store.sessions.values)
          s.id: s.status.name,
      },
      'markers': <String>[
        for (final TranscriptSegmentEntity s in store.segments.values)
          if (s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
            '${s.sessionId}/${s.source.name}/${s.id}: ${s.text}',
      ],
    });
    void dumpSegments() => log('segments', <String, Object?>{
      'list': <Map<String, Object?>>[
        for (final SessionEntity se in store.sessions.values)
          for (final TranscriptSegmentEntity s in store.segments.values.where(
            (TranscriptSegmentEntity x) => x.sessionId == se.id,
          ))
            <String, Object?>{
              'session': se.id,
              'src': s.source == AudioSource.input ? 'mic' : 'sys',
              't': s.timestampMs / 1000,
              'id': s.id,
              'text': s.text,
            },
      ],
    });

    if (mode == 'relaunch') {
      // Mirrors kernel(): sessions still active, repair, WAV repair, retry.
      final List<String> killed = <String>[
        for (final SessionEntity s in store.sessions.values)
          if (s.status == SessionStatus.active) s.id,
      ];
      log('relaunch_killed', <String, Object?>{'ids': killed});
      snap('relaunch_before');
      await RepairInterruptedSessionsUseCase(
        sessionRepository: store,
        transcriptRepository: store,
      ).invoke();
      for (final FileSystemEntity f in Directory(recordingsDir).listSync()) {
        if (f is File && f.path.endsWith('.wav')) {
          await WavRecorder.repair(f.path);
        }
      }
      snap('relaunch_after_repair');
      for (final String id in killed) {
        await retry.enqueue(id);
      }
      snap('relaunch_enqueued');
      await retry.retryPending();
      snap('relaunch_after_retry');
      dumpSegments();
      await retry.dispose();
      await closeProbeLog();
      return;
    }

    // Proxy + real data source (ports rewritten per source: mic 8018, sys 8019).
    final Proxy micProxy = Proxy('mic', 8018);
    final Proxy sysProxy = Proxy('sys', 8019);
    await micProxy.listen();
    await sysProxy.listen();
    final Map<String, StreamSubscription<String>> raw =
        <String, StreamSubscription<String>>{};
    WebSocketClient client(String src, int port) {
      final WebSocketClient c = WebSocketClient(
        connectChannel: (Uri uri) {
          log('connect', <String, Object?>{'src': src});
          return WebSocketChannel.connect(uri.replace(port: port));
        },
      );
      // Raw server messages (independent of the data source's pairing).
      raw[src] = c.messageStream.listen((String m) {
        final Map<String, dynamic> j = jsonDecode(m) as Map<String, dynamic>;
        if (j['type'] == 'response.audio_transcript.done') {
          log('raw_done', <String, Object?>{'src': src, 'text': j['text']});
        }
      }, onError: (Object _) {});
      return c;
    }

    final TranscriptionRemoteDataSourceImpl remote =
        TranscriptionRemoteDataSourceImpl(
          micClient: client('mic', 8018),
          systemClient: client('sys', 8019),
        );
    final FakeAudioCaptureChannel capture = FakeAudioCaptureChannel();
    final LiveTranscriptionService service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(
        channel: FakeProcessManagerChannel(),
      ),
      audioCaptureChannel: capture,
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      gapBackfill: backfill,
      gapBackfillRetry: retry,
    );
    final Map<String, String> seen = <String, String>{};
    transcription.segmentsStream.listen((List<TranscriptSegmentEntity> list) {
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
    service.finalisingRemainingStream.listen(
      (Duration d) =>
          log('finalising', <String, Object?>{'s': d.inMilliseconds / 1000}),
    );

    Future<void> start(String name) async {
      log('meeting_start', <String, Object?>{'name': name});
      await service.startTranscription(
        outputEnabled: true,
        serverCommand: 'voxmlx-serve',
        webSocketUrl: probeUrl,
      );
      log('meeting_started', <String, Object?>{
        'name': name,
        'session': transcription.currentSessionStream.valueOrNull?.id,
      });
    }

    Future<void> stop(String name) async {
      log('meeting_stop', <String, Object?>{'name': name});
      final Stopwatch sw = Stopwatch()..start();
      await service.stopTranscription();
      log('meeting_stopped', <String, Object?>{
        'name': name,
        'took_s': sw.elapsedMilliseconds / 1000,
      });
    }

    // Real-time feed of [seconds] from [dir]'s mic/sys timelines, from [from].
    bool feeding = false;
    Future<void> feed(
      String dir,
      double seconds, {
      double from = 0,
      Map<double, Future<void> Function()> faults =
          const <double, Future<void> Function()>{},
      String label = '',
    }) async {
      final Uint8List mic = readPcm('$dir/mic.wav');
      final Uint8List sys = readPcm('$dir/sys.wav');
      final int t0 = DateTime.now().millisecondsSinceEpoch;
      log('feed_start', <String, Object?>{
        'label': label,
        'dir': dir,
        'from': from,
        'seconds': seconds,
      });
      for (final MapEntry<double, Future<void> Function()> f
          in faults.entries) {
        Timer(Duration(milliseconds: (f.key * 1000).round()), () async {
          log('fault', <String, Object?>{'at': f.key, 'label': label});
          await f.value();
        });
      }
      feeding = true;
      final int first = (from * 10).floor();
      final int n = (seconds * 10).round();
      for (int i = 0; i < n && feeding; i++) {
        final int due = t0 + i * 100;
        final int wait = due - DateTime.now().millisecondsSinceEpoch;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        final int at = (first + i) * 3200;
        for (final (AudioSource src, Uint8List pcm)
            in <(AudioSource, Uint8List)>[
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
      log('feed_end', <String, Object?>{'label': label});
    }

    Future<void> both(Future<void> Function(Proxy) f) async {
      await f(micProxy);
      await f(sysProxy);
    }

    Future<void> waitNoMarkers(String step, {int seconds = 180}) async {
      final Stopwatch sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds &&
          store.segments.values.any(
            (TranscriptSegmentEntity s) =>
                s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      log('markers_gone', <String, Object?>{
        'step': step,
        'after_s': sw.elapsedMilliseconds / 1000,
        'left': store.segments.values
            .where(
              (TranscriptSegmentEntity s) =>
                  s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
            )
            .map((TranscriptSegmentEntity s) => s.text)
            .toList(),
      });
      snap('$step+wait');
    }

    final String live = '$audio/live';
    final String live60 = '$audio/live60';

    if (mode == 'b2b') {
      // A: refusal 60-120 s, stop at 125 s during catch-up; B 2 s later.
      await start('A');
      await feed(
        live,
        125,
        label: 'A',
        faults: <double, Future<void> Function()>{
          60: () => both((Proxy p) => p.refuse()),
          120: () => both((Proxy p) => p.reopen()),
        },
      );
      final Future<void> stopA = stop('A');
      await Future<void>.delayed(const Duration(seconds: 2));
      final Future<void> startB = start('B');
      await startB;
      await stopA;
      await feed(live60, 90, label: 'B');
      await stop('B');
      snap('after_B_stopped');
      await waitNoMarkers('after_B');
      dumpSegments();
    } else if (mode == 'D' || mode == 'long20') {
      // D: refusal 60-210 s over 300 s. long20: 20 min of live60 with a 3 s
      // mic cut at 5 min and a 45 s refusal at 12 min. Stop drains, then
      // the backfill runs as in the app.
      final bool d = mode == 'D';
      await start(mode);
      await feed(
        d ? live : live60,
        d ? 300 : 1200,
        label: mode,
        faults: d
            ? <double, Future<void> Function()>{
                60: () => both((Proxy p) => p.refuse()),
                210: () => both((Proxy p) => p.reopen()),
              }
            : <double, Future<void> Function()>{
                301.5: () => micProxy.refuse(),
                304.5: () => micProxy.reopen(),
                720: () => both((Proxy p) => p.refuse()),
                765: () => both((Proxy p) => p.reopen()),
              },
      );
      snap('before_stop');
      await stop(mode);
      snap('after_stop');
      await waitNoMarkers('after_stop', seconds: 60);
      dumpSegments();
    } else if (mode == 'yield') {
      // A: refusal from 20 s until its stop drain gives up -> gap -> backfill.
      await start('A');
      await feed(
        live,
        60,
        label: 'A',
        faults: <double, Future<void> Function()>{
          20: () => both((Proxy p) => p.refuse()),
        },
      );
      final Completer<void> backfillStarted = Completer<void>();
      final Timer watch = Timer.periodic(const Duration(milliseconds: 100), (
        Timer t,
      ) {
        if (store.segments.values.any(
              (TranscriptSegmentEntity s) =>
                  s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) &&
                  !s.id.endsWith('_pending'),
            ) &&
            !backfillStarted.isCompleted) {
          backfillStarted.complete();
        }
      });
      final Future<void> stopA = stop('A');
      await backfillStarted.future;
      watch.cancel();
      await both((Proxy p) => p.reopen());
      // Let the backfill get going, then request B.
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      snap('before_B');
      await start('B');
      await stopA;
      snap('B_started');
      await feed(live60, 40, label: 'B');
      await stop('B');
      snap('after_B_stopped');
      await waitNoMarkers('after_B', seconds: 120);
      serverStates.add(ServerState.ready); // a server-ready event, if any
      await Future<void>.delayed(const Duration(seconds: 1));
      await retry.dispose();
      snap('after_ready_event');
      dumpSegments();
    } else if (mode == 'kill') {
      // Refusal from 40 s, never lifted; kill the process at 80 s.
      await start('A');
      Timer(const Duration(seconds: 82), () {
        snap('before_kill');
        log('kill_self');
        Process.killPid(pid, ProcessSignal.sigkill);
      });
      await feed(
        live,
        120,
        label: 'A',
        faults: <double, Future<void> Function()>{
          40: () => both((Proxy p) => p.refuse()),
        },
      );
    } else if (mode == 'lang') {
      // Replays the long run's sys sentences 201 and 369, 5 times each,
      // on the same 100 ms grid as in the long run.
      final List<dynamic> sched =
          (jsonDecode(File('$live60/schedule.json').readAsStringSync())
                  as Map<String, dynamic>)['sys']
              as List<dynamic>;
      await start('L');
      for (final int idx in <int>[201, 369]) {
        final Map<String, dynamic> s = sched[idx] as Map<String, dynamic>;
        final double from = ((s['start'] as num) - 1.5);
        final double len = (s['end'] as num) - (s['start'] as num) + 4.5;
        for (int k = 0; k < 5; k++) {
          await feed(live60, len, from: from, label: 'sys$idx#$k');
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      await stop('L');
      await waitNoMarkers('after_L', seconds: 120);
      dumpSegments();
    }
    log('done_mode', <String, Object?>{'t': now()});
    await raw['mic']?.cancel();
    await raw['sys']?.cancel();
    await micProxy.close();
    await sysProxy.close();
    await closeProbeLog();
  }, timeout: Timeout.none);
}
