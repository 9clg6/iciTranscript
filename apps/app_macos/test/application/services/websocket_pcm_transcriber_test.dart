import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';

/// Tour 5, suite (b) : [WebSocketPcmTranscriber] contre une socket factice.
/// Un long intervalle part en morceaux courts (12 s au plus depuis le tour
/// 6), chacun commité puis attendu avant le suivant (comme le renvoi étalé) ; les
/// heures rendues partent du début de l'intervalle ; un serveur muet fait
/// échouer la retranscription en temps borné ; la socket est fermée après,
/// réussite ou échec.
void main() {
  /// [seconds] s de PCM16 16 kHz, numéroté par chunk de 100 ms.
  Uint8List pcm(int seconds) {
    final Uint8List data = Uint8List(seconds * 32000);
    final ByteData d = ByteData.sublistView(data);
    for (int c = 0; c * 3200 < data.length; c++) {
      d.setInt16(c * 3200, c, Endian.little);
    }
    return data;
  }

  // Tour 6 : morceaux de WebSocketPcmTranscriber.maxPiece (12 s) au plus,
  // coupés aux silences (sonde 4 : un morceau de 30 s occupait le serveur
  // séquentiel, un enregistrement attendait 8,8 s). L'intention reste :
  // tout l'intervalle transcrit une fois, dans l'ordre, chaque morceau
  // attendu avant le suivant, heures depuis le début de l'intervalle.
  test('70 s : morceaux de 12 s au plus, tout l intervalle une fois dans '
      'l ordre, un à la fois, heures depuis le début, socket fermée', () {
    fakeAsync((FakeAsync async) {
      final _ScriptedServer server = _ScriptedServer(async)
        ..answerAfter = const Duration(seconds: 2);
      final WebSocketPcmTranscriber transcriber = WebSocketPcmTranscriber(
        createClient: server.client,
      );
      List<({int offsetMs, String text})>? result;
      transcriber.transcribe(pcm(70)).then((r) => result = r);
      async.elapse(const Duration(minutes: 1));

      expect(result, isNotNull);
      final int maxBytes = WebSocketPcmTranscriber.maxPiece.inMilliseconds * 32;
      expect(server.bytesPerCommit.length, greaterThanOrEqualTo(6));
      expect(
        server.bytesPerCommit.every((int b) => b <= maxBytes),
        isTrue,
        reason: 'morceaux de 12 s au plus',
      );
      expect(
        server.bytesPerCommit.fold<int>(0, (int a, int b) => a + b),
        70 * 32000,
        reason: 'tout l intervalle, une fois',
      );
      int chunk = 0;
      final List<int> expectedFirst = <int>[];
      for (final int bytes in server.bytesPerCommit) {
        expectedFirst.add(chunk);
        chunk += bytes ~/ 3200;
      }
      expect(
        server.firstChunkOfCommit,
        expectedFirst,
        reason: 'morceaux contigus, dans l ordre',
      );
      expect(
        result!.map((p) => p.offsetMs),
        expectedFirst.map((int c) => c * 100),
        reason: 'heures depuis le début de l intervalle',
      );
      expect(result!.map((p) => p.text), <String>[
        for (int n = 1; n <= server.bytesPerCommit.length; n++) 'Morceau $n.',
      ]);
      expect(
        server.log.join(' '),
        matches(RegExp(r'^((append )+commit done ?)+$')),
        reason: 'chaque morceau attend son done avant le suivant',
      );
      expect(server.closed, isTrue);
    });
  });

  test('serveur muet : la retranscription échoue en temps borné et la '
      'socket est fermée', () {
    fakeAsync((FakeAsync async) {
      final _ScriptedServer server = _ScriptedServer(async)..answerAfter = null;
      final WebSocketPcmTranscriber transcriber = WebSocketPcmTranscriber(
        createClient: server.client,
      );
      Object? error;
      bool succeeded = false;
      transcriber
          .transcribe(pcm(10))
          .then<void>(
            (_) {
              succeeded = true;
            },
            onError: (Object e) {
              error = e;
            },
          );
      async.elapse(const Duration(seconds: 90));

      expect(succeeded, isFalse);
      expect(error, isNotNull, reason: 'échec au plus 90 s après l envoi');
      expect(server.closed, isTrue);
    });
  });
}

/// Serveur voxmlx factice : un `done` « Morceau n. » par commit final,
/// [answerAfter] après le commit (null : jamais).
final class _ScriptedServer {
  _ScriptedServer(this.async);

  final FakeAsync async;
  Duration? answerAfter;
  final List<String> log = <String>[];
  final List<int> bytesPerCommit = <int>[];
  final List<int> firstChunkOfCommit = <int>[];
  bool closed = false;
  int _bytes = 0;
  int? _first;
  int _commits = 0;
  late _Socket _socket;

  WebSocketClient client() => _socket = _Socket(this);

  void _onSend(String message) {
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      final Uint8List audio = base64Decode(json['audio'] as String);
      _first ??= ByteData.sublistView(audio).getInt16(0, Endian.little);
      _bytes += audio.length;
      log.add('append');
    } else if (json['type'] == 'input_audio_buffer.commit' &&
        json['final'] == true) {
      log.add('commit');
      bytesPerCommit.add(_bytes);
      firstChunkOfCommit.add(_first ?? -1);
      _bytes = 0;
      _first = null;
      final int n = ++_commits;
      final Duration? delay = answerAfter;
      if (delay == null) return;
      Timer(delay, () {
        if (closed) return;
        log.add('done');
        _socket.push(<String, Object>{
          'type': 'response.audio_transcript.done',
          'text': 'Morceau $n.',
        });
      });
    }
  }
}

final class _Socket extends WebSocketClient {
  _Socket(this._server);

  final _ScriptedServer _server;
  bool _connected = false;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  void push(Map<String, Object> event) => _messages.add(jsonEncode(event));

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async => _connected = true;

  @override
  void send(String message) {
    if (_connected) _server._onSend(message);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _server.closed = true;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _server.closed = true;
  }
}
