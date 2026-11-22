// Runs the real GapBackfillService + WebSocketPcmTranscriber on a live_probe
// run (its gaps, transcripts and WAVs) against a real voxmlx-serve.
// Not part of the suite: `flutter test tool/backfill_probe.dart` with
// RUN_DIR, RUN_NAME, OUT and URL in the environment. MODE=retry runs
// GapBackfillRetry instead: first attempt with the server absent, a
// simulated relaunch, then starts the server (SERVER_CMD, PROBE_DIR) and
// reports ready; `.backfill_pending.json` is snapshotted at each step.
import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';

class _MemoryTranscripts implements TranscriptRepository {
  final Map<String, TranscriptSegmentEntity> byId =
      <String, TranscriptSegmentEntity>{};

  @override
  Future<List<TranscriptSegmentEntity>> getBySessionId(String id) async =>
      byId.values
          .where((TranscriptSegmentEntity s) => s.sessionId == id)
          .toList()
        ..sort(
          (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
              a.timestampMs.compareTo(b.timestampMs),
        );

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity s) async =>
      byId[s.id] = s;

  @override
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> list,
  ) async => <TranscriptSegmentEntity>[for (final s in list) await save(s)];

  @override
  Future<void> deleteById(String id) async => byId.remove(id);

  @override
  Future<void> deleteBySessionId(String id) async =>
      byId.removeWhere((_, TranscriptSegmentEntity s) => s.sessionId == id);
}

void main() {
  test('backfill probe', () async {
    final Map<String, String> env = Platform.environment;
    final String dir = env['RUN_DIR']!;
    final String run = env['RUN_NAME']!;
    final List<Map<String, dynamic>> ev = File('$dir/$run.jsonl')
        .readAsLinesSync()
        .map((String l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    final _MemoryTranscripts repo = _MemoryTranscripts();
    AudioSource src(Object? s) =>
        s == 'mic' ? AudioSource.input : AudioSource.output;
    int k = 0;
    for (final Map<String, dynamic> e in ev) {
      if (e['ev'] == 'done' && e['win_start_s'] != null) {
        await repo.save(
          TranscriptSegmentEntity(
            id: 'seg_${k++}',
            sessionId: run,
            source: src(e['src']),
            text: e['text'] as String,
            timestampMs: ((e['win_start_s'] as num) * 1000).round(),
            createdAt: DateTime.now(),
          ),
        );
      } else if (e['ev'] == 'gap') {
        final int start = ((e['start_s'] as num) * 1000).round();
        final int end = ((e['end_s'] as num) * 1000).round();
        await repo.save(
          TranscriptSegmentEntity(
            id: 'gap_${k++}',
            sessionId: run,
            source: src(e['src']),
            text: LiveTranscriptionService.gapMarkerText(start, end),
            timestampMs: start,
            createdAt: DateTime.now(),
          ),
        );
      }
    }
    final GapBackfillService service = GapBackfillService(
      transcriber: WebSocketPcmTranscriber(url: env['URL']!),
      transcripts: repo,
      isRecording: () => false,
    );
    final Stopwatch sw = Stopwatch()..start();
    Object? error;
    Object? outcome;
    final List<Map<String, Object?>> steps = <Map<String, Object?>>[];
    final File pending = File('$dir/.backfill_pending.json');
    void snap(String step) => steps.add(<String, Object?>{
      'step': step,
      't': sw.elapsedMilliseconds / 1000,
      'pending': pending.existsSync() ? pending.readAsStringSync() : null,
      'markers': repo.byId.values
          .where(
            (TranscriptSegmentEntity s) =>
                s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )
          .length,
    });
    try {
      if (env['MODE'] == 'retry') {
        final StreamController<ServerState> states =
            StreamController<ServerState>.broadcast();
        final GapBackfillRetry retry = GapBackfillRetry(
          backfill: service,
          serverStates: states.stream,
          isRecording: () => false,
          recordingsDirectory: dir,
        );
        snap('before');
        await retry.afterSession(run);
        snap('after_session_server_absent');
        await retry.retryPending();
        snap('relaunch_server_absent');
        await retry.retryPending();
        snap('second_relaunch_server_absent');
        final Process p = await Process.start('/bin/sh', <String>[
          '-c',
          'exec ${env['SERVER_CMD']} >> ${env['PROBE_DIR']}/server.log 2>&1',
        ], mode: ProcessStartMode.detached);
        File('${env['PROBE_DIR']}/server.pid').writeAsStringSync('${p.pid}');
        final HttpClient http = HttpClient();
        while (true) {
          try {
            final HttpClientResponse r = await (await http.getUrl(
              Uri.parse('http://127.0.0.1:8017/health'),
            )).close();
            if (r.statusCode == 200) break;
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        snap('server_ready');
        states.add(ServerState.ready);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await retry.dispose(); // waits for the queued attempt
        snap('after_ready_retry');
      } else {
        final BackfillOutcome o = await service.backfill(
          run,
          recordingsDirectory: dir,
        );
        outcome = <String, Object?>{
          'markersLeft': o.markersLeft,
          'reachedServer': o.reachedServer,
        };
      }
    } catch (e) {
      error = e;
    }
    final List<TranscriptSegmentEntity> after = await repo.getBySessionId(run);
    File(env['OUT']!).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'elapsed_s': sw.elapsedMilliseconds / 1000,
        'error': error?.toString(),
        'outcome': outcome,
        'steps': steps,
        'segments': <Map<String, Object?>>[
          for (final TranscriptSegmentEntity s in after)
            <String, Object?>{
              'id': s.id,
              'src': s.source == AudioSource.input ? 'mic' : 'sys',
              't': s.timestampMs / 1000,
              'text': s.text,
            },
        ],
      }),
    );
  }, timeout: Timeout.none);
}
