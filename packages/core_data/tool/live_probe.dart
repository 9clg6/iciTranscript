// Drives the real TranscriptionRemoteDataSourceImpl + WebSocketClient against
// a real voxmlx-serve through a fault-injecting TCP proxy. See
// tool/server_probe/README.md at the repository root.
//
// dart run tool/live_probe.dart <scenario> <audioDir> <out.jsonl> <probeDir>
// scenario: A (none) | B (cut mic 3 s x4) | C (refuse 20 s, 60 s) |
//           D (refuse 150 s) | E (stall 30 s, 90 s) | F (kill + restart server)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const int serverPort = 8017;
final int seconds = int.parse(Platform.environment['LIVE_SECONDS'] ?? '300');
const int chunkBytes = 3200; // 100 ms PCM16 mono 16 kHz

late final IOSink _log;
late final int _epoch0;

double _t() => (DateTime.now().millisecondsSinceEpoch - _epoch0) / 1000;

void log(String ev, [Map<String, Object?> fields = const <String, Object?>{}]) {
  _log.writeln(jsonEncode(<String, Object?>{'t': _t(), 'ev': ev, ...fields}));
}

/// TCP proxy to the server: cut, refuse (port closed) or stall (no bytes
/// forwarded, both ways, data kept by TCP back-pressure).
class Proxy {
  Proxy(this.name, this.port);

  final String name;
  final int port;
  ServerSocket? _server;
  bool _stalled = false;
  final List<List<Object>> _conns = <List<Object>>[];
  final Set<List<Object>> _cutPairs = Set<List<Object>>.identity();

  Future<void> listen() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_onClient);
  }

  Future<void> _onClient(Socket client) async {
    Socket up;
    try {
      up = await Socket.connect(InternetAddress.loopbackIPv4, serverPort);
    } catch (_) {
      log('proxy_upstream_refused', <String, Object?>{'src': name});
      client.destroy();
      return;
    }
    // A write to a socket the other side already closed must not kill the
    // harness: drop the pair instead.
    void pipe(Socket to, Uint8List d) {
      try {
        to.add(d);
      } catch (_) {
        client.destroy();
        up.destroy();
      }
    }

    final List<Object> pair = <Object>[client, up];
    void closedBy(String side) {
      if (!_cutPairs.contains(pair)) {
        log('closed_by_$side', <String, Object?>{'src': name});
      }
      client.destroy();
      up.destroy();
    }

    final StreamSubscription<Uint8List> a = client.listen(
      (Uint8List d) => pipe(up, d),
      onDone: () => closedBy('client'),
      onError: (Object _) => closedBy('client'),
    );
    final StreamSubscription<Uint8List> b = up.listen(
      (Uint8List d) => pipe(client, d),
      onDone: () => closedBy('server'),
      onError: (Object _) => closedBy('server'),
    );
    if (_stalled) {
      a.pause();
      b.pause();
    }
    pair.addAll(<Object>[a, b]);
    _conns.add(pair);
  }

  void cut() {
    for (final List<Object> c in _conns) {
      _cutPairs.add(c);
      (c[0] as Socket).destroy();
      (c[1] as Socket).destroy();
    }
    _conns.clear();
    log('proxy_cut', <String, Object?>{'src': name});
  }

  Future<void> refuse() async {
    await _server?.close();
    _server = null;
    cut();
    log('proxy_refuse', <String, Object?>{'src': name});
  }

  Future<void> reopen() async {
    await listen();
    log('proxy_open', <String, Object?>{'src': name});
  }

  void stall(bool on) {
    _stalled = on;
    for (final List<Object> c in _conns) {
      for (final Object s in c.sublist(2)) {
        final StreamSubscription<Uint8List> sub =
            s as StreamSubscription<Uint8List>;
        on ? sub.pause() : sub.resume();
      }
    }
    log(on ? 'proxy_stall' : 'proxy_unstall', <String, Object?>{'src': name});
  }

  Future<void> close() async {
    await _server?.close();
    cut();
  }
}

Uint8List wavHeader(int dataBytes) {
  final ByteData h = ByteData(44);
  void tag(int at, String s) {
    for (int i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return h.buffer.asUint8List();
}

Uint8List readPcm(String path) {
  final Uint8List b = File(path).readAsBytesSync();
  final ByteData d = ByteData.sublistView(b);
  int i = 12;
  while (i + 8 <= b.length) {
    final String id = ascii.decode(b.sublist(i, i + 4));
    final int size = d.getUint32(i + 4, Endian.little);
    if (id == 'data') return Uint8List.sublistView(b, i + 8, i + 8 + size);
    i += 8 + size + (size & 1);
  }
  throw StateError('no data chunk in $path');
}

Future<void> main(List<String> args) async {
  await runZonedGuarded(() => _run(args), (Object e, StackTrace st) {
    stderr.writeln('harness_error: $e\n$st');
    log('harness_error', <String, Object?>{'err': '$e'});
  });
}

Future<void> _run(List<String> args) async {
  final String scenario = args[0];
  final String audioDir = args[1];
  final String probeDir = args[3];
  _log = File(args[2]).openWrite();
  final Uint8List mic = readPcm('$audioDir/mic.wav');
  final Uint8List sys = readPcm('$audioDir/sys.wav');
  final Map<String, dynamic> sched =
      jsonDecode(File('$audioDir/schedule.json').readAsStringSync())
          as Map<String, dynamic>;

  final Proxy micProxy = Proxy('mic', 8018);
  final Proxy sysProxy = Proxy('sys', 8019);
  await micProxy.listen();
  await sysProxy.listen();

  WebSocketClient client(String src, int port) {
    final WebSocketClient c = WebSocketClient(
      connectChannel: (Uri uri) {
        log('connect', <String, Object?>{'src': src});
        return WebSocketChannel.connect(uri.replace(port: port));
      },
    );
    c.onClosed.listen((_) => log('ws_onclosed', <String, Object?>{'src': src}));
    return c;
  }

  final TranscriptionRemoteDataSourceImpl ds =
      TranscriptionRemoteDataSourceImpl(
        micClient: client('mic', 8018),
        systemClient: client('sys', 8019),
      );
  _epoch0 = DateTime.now().millisecondsSinceEpoch;
  log('start', <String, Object?>{'scenario': scenario, 'seconds': seconds});

  double? rel(int? ms) => ms == null ? null : (ms - _epoch0) / 1000;

  void onEvent(String src, TranscriptEventRemoteModel e) {
    if (e.type == 'response.audio_transcript.done') {
      final UtteranceWindow? w = ds.windowOf(e);
      log('done', <String, Object?>{
        'src': src,
        'text': e.text ?? '',
        'win_start_s': rel(w?.startMs),
        'win_end_s': rel(w?.endMs),
      });
    } else if (e.type == utteranceResentEventType ||
        e.type == utteranceLostEventType) {
      log('control', <String, Object?>{'src': src, 'type': e.type});
    }
  }

  final List<StreamSubscription<Object?>> subs = <StreamSubscription<Object?>>[
    ds.transcriptionStream.listen(
      (TranscriptEventRemoteModel e) => onEvent('mic', e),
      onError: (Object e) =>
          log('stream_error', <String, Object?>{'src': 'mic', 'err': '$e'}),
    ),
    ds.systemTranscriptionStream.listen(
      (TranscriptEventRemoteModel e) => onEvent('sys', e),
      onError: (Object e) =>
          log('stream_error', <String, Object?>{'src': 'sys', 'err': '$e'}),
    ),
    ds.audioGaps.listen(
      (dynamic g) => log('gap', <String, Object?>{
        'src': g.source == AudioSource.input ? 'mic' : 'sys',
        'start_s': rel(g.startMs as int),
        'end_s': rel(g.endMs as int),
      }),
    ),
    ds.connectionState.listen(
      (Object s) => log('state', <String, Object?>{'state': '$s'}),
    ),
  ];
  await ds.connect(url: 'ws://127.0.0.1:8018/v1/realtime');

  final Timer sampler = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) => log('buffered', <String, Object?>{
      'mic': ds.bufferedAudio(AudioSource.input).inMilliseconds / 1000,
      'sys': ds.bufferedAudio(AudioSource.output).inMilliseconds / 1000,
    }),
  );

  // Fault schedule: (second, action).
  Future<void> both(Future<void> Function(Proxy) f) async {
    await f(micProxy);
    await f(sysProxy);
  }

  Future<void> restartServer() async {
    final Process p = await Process.start('/bin/sh', <String>[
      '-c',
      'HF_HUB_OFFLINE=1 exec perl -e \'setpgrp(0,0); exec @ARGV\' uvx '
          '--offline --python 3.12 --from '
          "'git+https://github.com/T0mSIlver/voxmlx.git@2ea0639570e447493d04349d96a41f71c031ae0d[server]' "
          'voxmlx-serve --model T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit '
          '--port $serverPort >> $probeDir/server.log 2>&1',
    ], mode: ProcessStartMode.detached);
    File('$probeDir/server.pid').writeAsStringSync('${p.pid}');
    log('server_start', <String, Object?>{'pgid': p.pid});
  }

  List<double> mids(String src) => (sched[src] as List<dynamic>)
      .map((dynamic s) => ((s['start'] as num) + (s['end'] as num)) / 2)
      .cast<double>()
      .toList();
  final Map<String, List<double>> allMids = <String, List<double>>{
    'mic': mids('mic'),
    'sys': mids('sys'),
  };
  double midNear(double t, [String src = 'mic']) => allMids[src]!.reduce(
    (double a, double b) => (a - t).abs() < (b - t).abs() ? a : b,
  );

  Future<void> killServer() async {
    final String pgid = File('$probeDir/server.pid').readAsStringSync().trim();
    await Process.run('kill', <String>['--', '-$pgid']);
    log('server_kill', <String, Object?>{'pgid': pgid});
  }

  // Long run: a 3 s cut every ~10 min on alternating sources, a 45 s
  // refusal at 30 min, a server kill + restart at 45 min.
  final List<(double, String)> longCuts = <(double, String)>[
    (600, 'mic'),
    (1200, 'sys'),
    (2100, 'mic'),
    (3000, 'sys'),
    (3400, 'mic'),
  ];

  final Map<double, Future<void> Function()> faults =
      <double, Future<void> Function()>{
        if (scenario == 'B')
          for (final double t in <double>[
            40,
            110,
            180,
            250,
          ]) ...<double, Future<void> Function()>{
            midNear(t): () async => micProxy.refuse(),
            midNear(t) + 3: () async => micProxy.reopen(),
          },
        if (scenario == 'C') ...<double, Future<void> Function()>{
          60: () => both((Proxy p) => p.refuse()),
          80: () => both((Proxy p) => p.reopen()),
          150: () => both((Proxy p) => p.refuse()),
          210: () => both((Proxy p) => p.reopen()),
        },
        if (scenario == 'D') ...<double, Future<void> Function()>{
          60: () => both((Proxy p) => p.refuse()),
          210: () => both((Proxy p) => p.reopen()),
        },
        if (scenario == 'E') ...<double, Future<void> Function()>{
          60: () async => both((Proxy p) async => p.stall(true)),
          90: () async => both((Proxy p) async => p.stall(false)),
          150: () async => both((Proxy p) async => p.stall(true)),
          240: () async => both((Proxy p) async => p.stall(false)),
        },
        if (scenario == 'F') ...<double, Future<void> Function()>{
          100: killServer,
          115: restartServer,
        },
        if (scenario.startsWith('G')) ...<double, Future<void> Function()>{
          60: () => both((Proxy p) => p.refuse()),
          120: () => both((Proxy p) => p.reopen()),
        },
        if (scenario == 'L') ...<double, Future<void> Function()>{
          for (final (double t, String src)
              in longCuts) ...<double, Future<void> Function()>{
            midNear(t, src): () =>
                (src == 'mic' ? micProxy : sysProxy).refuse(),
            midNear(t, src) + 3: () =>
                (src == 'mic' ? micProxy : sysProxy).reopen(),
          },
          1800: () => both((Proxy p) => p.refuse()),
          1845: () => both((Proxy p) => p.reopen()),
          2700: killServer,
          2715: restartServer,
        },
      };
  for (final MapEntry<double, Future<void> Function()> f in faults.entries) {
    Timer(Duration(milliseconds: (f.key * 1000).round()), () async {
      log('fault', <String, Object?>{'at': f.key});
      await f.value();
    });
  }

  Future<void> sampleFootprint() async {
    final String pgid = File('$probeDir/server.pid').readAsStringSync().trim();
    final String ps =
        (await Process.run('ps', <String>[
              '-o',
              'pid=,comm=',
              '-g',
              pgid,
            ])).stdout
            as String;
    final String? pid = ps
        .split('\n')
        .where((String l) => l.contains('Python'))
        .map((String l) => l.trim().split(' ').first)
        .firstOrNull;
    if (pid == null) return log('footprint', <String, Object?>{'mb': null});
    final String out =
        (await Process.run('footprint', <String>[pid])).stdout as String;
    final RegExpMatch? m = RegExp(
      r'Footprint: ([\d.]+) (MB|GB)',
    ).firstMatch(out);
    final double? mb = m == null
        ? null
        : double.parse(m.group(1)!) * (m.group(2) == 'GB' ? 1024 : 1);
    log('footprint', <String, Object?>{'pid': pid, 'mb': mb});
  }

  await sampleFootprint();
  final Timer footprints = Timer.periodic(
    const Duration(minutes: 5),
    (_) => unawaited(sampleFootprint()),
  );

  // Real-time feed: both sources, one 100 ms chunk each every 100 ms.
  final int n = seconds * 10;
  for (int i = 0; i < n; i++) {
    final int due = _epoch0 + i * 100;
    final int wait = due - DateTime.now().millisecondsSinceEpoch;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    for (final (AudioSource src, Uint8List pcm) in <(AudioSource, Uint8List)>[
      (AudioSource.input, mic),
      (AudioSource.output, sys),
    ]) {
      final int at = i * chunkBytes;
      if (at + chunkBytes > pcm.length) continue;
      ds.sendAudio(
        AudioChunk(
          source: src,
          data: Uint8List.sublistView(pcm, at, at + chunkBytes),
          timestampMs: due,
        ),
      );
    }
  }
  log('feed_end');
  // Mirrors LiveTranscriptionService stop: final commit, then wait for the
  // catch-up up to its 120 s limit, or until the user skips the wait.
  final int drainLimit = int.parse(
    Platform.environment['DRAIN_LIMIT'] ?? '120',
  );
  final int? skipAfter = int.tryParse(
    Platform.environment['STOP_SKIP_AFTER'] ?? '',
  );
  final int limit = skipAfter ?? drainLimit;
  final DateTime stopAt = DateTime.now();
  ds.sendCommit(isFinal: true);
  final DateTime giveUp = stopAt.add(Duration(seconds: limit));
  while (ds.activeSources.isNotEmpty && DateTime.now().isBefore(giveUp)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  log('drained', <String, Object?>{
    'waited_s': DateTime.now().difference(stopAt).inMilliseconds / 1000,
    'skipped': skipAfter != null && ds.activeSources.isNotEmpty,
    'active': ds.activeSources.map((AudioSource s) => s.name).toList(),
    'unacked_mic':
        ds.unacknowledgedAudio(AudioSource.input).inMilliseconds / 1000,
    'unacked_sys':
        ds.unacknowledgedAudio(AudioSource.output).inMilliseconds / 1000,
  });
  sampler.cancel();
  footprints.cancel();
  await sampleFootprint();
  // The WAVs the app would have written: every captured chunk, 44-byte header.
  final String stem = args[2].replaceAll(RegExp(r'\.jsonl$'), '');
  for (final (String track, Uint8List pcm) in <(String, Uint8List)>[
    ('mic', mic),
    ('system', sys),
  ]) {
    final int len = (seconds * 10 * chunkBytes).clamp(
      0,
      pcm.length - pcm.length % chunkBytes,
    );
    File('${stem}_$track.wav').writeAsBytesSync(<int>[
      ...wavHeader(len),
      ...Uint8List.sublistView(pcm, 0, len),
    ]);
  }
  await ds.disconnect();
  for (final StreamSubscription<Object?> s in subs) {
    await s.cancel();
  }
  await micProxy.close();
  await sysProxy.close();
  await _log.flush();
  await _log.close();
  exit(0);
}
