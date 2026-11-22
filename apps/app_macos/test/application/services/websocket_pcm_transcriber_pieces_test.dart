import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';

// Tour 6, point 3 (sonde 4) : des morceaux fixes de 30 s coupaient des
// phrases (« school, and then… ») et un morceau déjà envoyé occupait le
// serveur séquentiel : un enregistrement qui démarrait attendait 8,8 s sa
// connexion. Le PCM est découpé aux silences (la porte RMS existante, par
// pas de 100 ms) en morceaux de [WebSocketPcmTranscriber.maxPiece] au plus
// (12 s, une constante) ; jamais en pleine parole quand la fenêtre contient
// un silence ; une phrase plus courte que la borne n'est jamais coupée.
// Avec des morceaux aussi courts, un démarrage n'attend qu'environ un
// morceau (le serveur traite ~2× le temps réel).
void main() {
  const int speechAmplitude = 1200;

  /// Phrases de [runs] chunks de 100 ms, séparées par 1 s de silence.
  /// Chaque chunk porte son numéro dans son premier échantillon.
  ({Uint8List pcm, List<bool> voiced}) meeting(List<int> runs) {
    final List<bool> voiced = <bool>[];
    for (int r = 0; r < runs.length; r++) {
      voiced.addAll(List<bool>.filled(runs[r], true));
      if (r < runs.length - 1) voiced.addAll(List<bool>.filled(10, false));
    }
    final Uint8List pcm = Uint8List(voiced.length * 3200);
    final ByteData d = ByteData.sublistView(pcm);
    for (int c = 0; c < voiced.length; c++) {
      if (voiced[c]) {
        for (int o = 2; o < 3200; o += 2) {
          d.setInt16(c * 3200 + o, speechAmplitude, Endian.little);
        }
      }
      d.setInt16(c * 3200, c, Endian.little);
    }
    return (pcm: pcm, voiced: voiced);
  }

  test('la borne des morceaux est de 12 s', () {
    expect(WebSocketPcmTranscriber.maxPiece, const Duration(seconds: 12));
  });

  test('morceaux coupés aux silences, 12 s au plus, phrases courtes '
      'entières, tout envoyé une fois dans l ordre', () {
    fakeAsync((FakeAsync async) {
      // 7 s, 4 s, 9 s, 3 s, 20 s sans pause, 5 s.
      final ({Uint8List pcm, List<bool> voiced}) m = meeting(<int>[
        70,
        40,
        90,
        30,
        200,
        50,
      ]);
      final _Server server = _Server();
      List<({int offsetMs, String text})>? result;
      WebSocketPcmTranscriber(
        url: 'ws://test',
        createClient: server.client,
      ).transcribe(m.pcm).then((r) => result = r);
      async.elapse(const Duration(minutes: 2));

      expect(result, isNotNull);
      final List<List<int>> pieces = server.pieces;
      final int maxChunks =
          WebSocketPcmTranscriber.maxPiece.inMilliseconds ~/ 100;
      expect(
        pieces.every((List<int> p) => p.length <= maxChunks),
        isTrue,
        reason: 'morceaux de 12 s au plus',
      );
      expect(
        pieces.expand((List<int> p) => p).toList(),
        List<int>.generate(m.voiced.length, (int i) => i),
        reason: 'tout le PCM, une fois, dans l ordre',
      );

      for (int k = 1; k < pieces.length; k++) {
        final int b = pieces[k].first;
        final bool silenceInWindow = pieces[k - 1].any((int c) => !m.voiced[c]);
        if (silenceInWindow) {
          expect(
            !m.voiced[b] || !m.voiced[b - 1],
            isTrue,
            reason:
                'coupe au chunk $b en pleine parole alors qu un '
                'silence existait',
          );
        }
      }

      // Chaque phrase de 12 s au plus tient dans un seul morceau.
      int start = 0;
      for (int c = 0; c <= m.voiced.length; c++) {
        final bool inSpeech = c < m.voiced.length && m.voiced[c];
        if (inSpeech && (c == 0 || !m.voiced[c - 1])) start = c;
        if (!inSpeech && c > 0 && m.voiced[c - 1] && c - start <= maxChunks) {
          final Set<int> holders = <int>{
            for (int i = start; i < c; i++)
              pieces.indexWhere((List<int> p) => p.contains(i)),
          };
          expect(holders, hasLength(1), reason: 'phrase $start–$c coupée');
        }
      }

      expect(
        result!.map((p) => p.offsetMs),
        pieces.map((List<int> p) => p.first * 100),
        reason: 'heure de chaque morceau depuis le début du PCM',
      );
    });
  });
}

/// Serveur factice : relit les numéros de chunks de chaque morceau, répond
/// « Morceau n. » 100 ms après chaque commit final.
final class _Server {
  final List<List<int>> pieces = <List<int>>[];
  List<int> _current = <int>[];
  late _Socket _socket;

  WebSocketClient client() => _socket = _Socket(this);

  void _onSend(String message) {
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      final Uint8List audio = base64Decode(json['audio'] as String);
      final ByteData d = ByteData.sublistView(audio);
      for (int o = 0; o + 3200 <= audio.length; o += 3200) {
        _current.add(d.getInt16(o, Endian.little));
      }
    } else if (json['type'] == 'input_audio_buffer.commit' &&
        json['final'] == true) {
      pieces.add(_current);
      _current = <int>[];
      final int n = pieces.length;
      Timer(const Duration(milliseconds: 100), () {
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

  final _Server _server;
  bool _connected = false;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  void push(Map<String, Object> event) {
    if (_connected) _messages.add(jsonEncode(event));
  }

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
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> dispose() async => _connected = false;
}
