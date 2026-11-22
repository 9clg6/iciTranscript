// Shared by live_probe.dart and apps/app_macos/tool/service_probe.dart:
// timestamped JSONL log, fault-injecting TCP proxy, WAV helpers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int serverPort = 8017;
final int seconds = int.parse(Platform.environment['LIVE_SECONDS'] ?? '300');
const int chunkBytes = 3200; // 100 ms PCM16 mono 16 kHz

late final IOSink _log;
late final int _epoch0;

/// Opens the run log; times are seconds since [epoch0].
void initProbeLog(String path, int epoch0) {
  _log = File(path).openWrite();
  _epoch0 = epoch0;
}

/// Flushes and closes the run log.
Future<void> closeProbeLog() async {
  await _log.flush();
  await _log.close();
}

/// Start of the run, ms since epoch.
int get probeEpoch0 => _epoch0;

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
