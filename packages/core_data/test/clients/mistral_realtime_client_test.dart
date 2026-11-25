import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../fixtures/mistral_probe.dart';

/// Moteur EN LIGNE : Mistral Voxtral temps réel, sous la couche de
/// fiabilité existante (tampon non acquitté, fenêtres, pertes, reconnexion
/// à borne adaptative, attente à l'arrêt), INCHANGÉE. Rejoue la sonde réelle
/// (test/fixtures/mistral_probe.dart, sans clé).
///
/// API supposée : `MistralRealtimeClient extends WebSocketClient`
/// (`package:core_data/clients/mistral_realtime_client.dart`) :
/// `MistralRealtimeClient({required apiKey, required transport,
/// int targetStreamingDelayMs = defaultStreamingDelayMs, String?
/// language})` ; `apiKey` rend la clé (lue à chaque connexion, peut être
/// nulle) ; `transport` crée la socket brute à partir des en-têtes HTTP ;
/// constantes `model` (`voxtral-mini-transcribe-realtime-3-0`), `url`,
/// `defaultStreamingDelayMs` (80), `keepAliveEvery` ; exception
/// `MistralKeyRejected`.
///
/// CORRESPONDANCE (d'après la sonde réelle) :
/// - `connect(url)` ignore l'URL locale : ouvre [MistralRealtimeClient.url]
///   avec l'en-tête `Authorization: Bearer` + clé ; premier message
///   `session.update` (`audio_format` pcm_s16le / 16000,
///   `target_streaming_delay_ms` 80) avant tout audio ; connecté une fois
///   `session.updated` reçu ;
/// - `input_audio_buffer.append` → `input_audio.append`, même base64 ;
/// - le serveur n'envoie QUE des `transcription.text.delta` (pas de
///   segment, pas de tour) : ils deviennent nos
///   `response.audio_transcript.delta` ;
/// - LES PHRASES SONT FAITES PAR OATS : règle — un `done` par fin d'énoncé
///   de notre porte de silence (commit final, 1,2 s après la dernière
///   parole) ; son texte = deltas reçus depuis le `done` précédent ; il
///   part 500 ms après le dernier delta qui suit la fin d'énoncé (au plus
///   3 s après elle) : le reste de la phrase arrive ~0,28 s après sa fin
///   (délai 80 ms). Le commit OpenAI n'est jamais envoyé ;
/// - PAUSES : sans audio pendant 30 s le serveur répond `error` 3804 puis
///   ferme (1011) ; le client envoie donc du silence (`input_audio.append`
///   de zéros) pendant les pauses, au moins toutes les
///   [MistralRealtimeClient.keepAliveEvery] (5 s au plus) ;
/// - ARRÊT : `disconnect()` envoie `input_audio.end` ; `transcription.done`
///   (texte entier, `segments: []`) arrive ~0,8 s plus tard, puis la socket
///   se ferme sans trame de fermeture (1006) ~2 s après : FIN NORMALE — ni
///   coupure, ni perte, ni reconnexion ; le texte de ce `done` ne refait
///   pas les phrases déjà rendues ;
/// - `error` (3804, autre) ou socket fermée en cours de réunion → coupure :
///   la couche de fiabilité reconnecte et renvoie ;
/// - clé refusée (HTTP 401 à la poignée de main, ou `error` 401) →
///   `MistralKeyRejected`, pas de tempête de reconnexions.
const String _key = 'mistral-test-SECRET-0123456789';

/// Delta enregistré, rattaché au chunk d'audio qui l'a produit (au plus
/// tard la fin de sa phrase) : le faux serveur l'envoie 300 ms après avoir
/// reçu ce chunk, comme le vrai (~0,28 s).
final List<({int anchorId, String text})> _deltas =
    <({int anchorId, String text})>[
      for (final ({int atMs, String text}) d in mistralProbeDeltas)
        () {
          final ({int startMs, int endMs, String text}) s =
              mistralProbeSentences.lastWhere(
                (({int startMs, int endMs, String text}) s) =>
                    s.startMs <= d.atMs,
                orElse: () => mistralProbeSentences.first,
              );
          final int anchorMs = math.max(
            s.startMs,
            math.min(d.atMs - 300, s.endMs - 100),
          );
          return (anchorId: anchorMs ~/ 100, text: d.text);
        }(),
    ];

final class _MistralServer {
  _MistralServer(this.async);

  final FakeAsync async;
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<String> urls = <String>[];
  final List<_Conn> connections = <_Conn>[];
  final List<Duration> connectAttempts = <Duration>[];
  bool refuseKey = false;
  bool accepting = true;
  int timeouts3804 = 0;
  _Conn? get live => connections.isEmpty ? null : connections.last;

  final List<_MistralSocket> sockets = <_MistralSocket>[];

  WebSocketClient transport(Map<String, String> h) {
    headers.add(Map<String, String>.of(h));
    final _MistralSocket s = _MistralSocket(this);
    sockets.add(s);
    return s;
  }
}

/// Une connexion vue du serveur.
final class _Conn {
  final List<({String type, Map<String, dynamic> json})> sent =
      <({String type, Map<String, dynamic> json})>[];
  final List<Duration> appendTimes = <Duration>[];
  final Set<int> ids = <int>{};
  final Set<int> deltasSent = <int>{};
  final StringBuffer text = StringBuffer();
}

final class _MistralSocket extends WebSocketClient {
  _MistralSocket(this._server);

  final _MistralServer _server;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<void> _closed = StreamController<void>.broadcast();
  bool _connected = false;
  late _Conn _conn;
  Timer? _silence;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  void push(Map<String, Object?> event) {
    if (_connected) _messages.add(jsonEncode(event));
  }

  /// Coupure réseau, ou fermeture du serveur (1006, 1011).
  void close() {
    if (!_connected) return;
    _connected = false;
    _silence?.cancel();
    _closed.add(null);
  }

  void fail3804() {
    push(<String, Object?>{
      'type': 'error',
      'error': <String, Object?>{
        'code': 3804,
        'message': 'Timeout waiting for response from streaming transcription.',
      },
    });
    _server.timeouts3804++;
    close(); // 1011
  }

  void _armSilence() {
    _silence?.cancel();
    _silence = Timer(const Duration(seconds: 30), fail3804);
  }

  @override
  Future<void> connect(String url) async {
    _server.connectAttempts.add(_server.async.elapsed);
    _server.urls.add(url);
    if (_server.refuseKey) {
      throw WebSocketException(
        "Connection to '$url' was not upgraded to websocket, HTTP status "
        'code: 401',
      );
    }
    if (!_server.accepting) throw const SocketException('Connection refused');
    _connected = true;
    _conn = _Conn();
    _server.connections.add(_conn);
    _armSilence();
    scheduleMicrotask(
      () => push(<String, Object?>{
        'type': 'session.created',
        'session': <String, Object?>{},
      }),
    );
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    final String type = json['type'] as String;
    _conn.sent.add((type: type, json: json));
    switch (type) {
      case 'session.update':
        scheduleMicrotask(
          () => push(<String, Object?>{
            'type': 'session.updated',
            'session': json['session'],
          }),
        );
      case 'input_audio.append':
        _conn.appendTimes.add(_server.async.elapsed);
        _armSilence();
        final Uint8List audio = base64Decode(json['audio'] as String);
        if (audio.every((int b) => b == 0)) return; // silence de maintien
        final ByteData d = ByteData.sublistView(audio);
        final int id =
            d.getInt16(0, Endian.little) + (d.getInt16(2, Endian.little) << 15);
        _conn.ids.add(id);
        final _Conn conn = _conn;
        for (int k = 0; k < _deltas.length; k++) {
          if (_deltas[k].anchorId != id || conn.deltasSent.contains(k)) {
            continue;
          }
          conn.deltasSent.add(k);
          Timer(const Duration(milliseconds: 300), () {
            if (!_connected || !identical(conn, _conn)) return;
            conn.text.write(_deltas[k].text);
            push(<String, Object?>{
              'type': 'transcription.text.delta',
              'text': _deltas[k].text,
            });
          });
        }
      case 'input_audio.end':
        _silence?.cancel();
        final _Conn conn = _conn;
        Timer(const Duration(milliseconds: mistralProbeDoneAfterEndMs), () {
          push(<String, Object?>{
            'type': 'transcription.done',
            'model': mistralProbeModel,
            'text': conn.text.toString(),
            'segments': <Object>[],
            'language': null,
          });
          Timer(
            const Duration(milliseconds: mistralProbeCloseAfterDoneMs),
            close, // 1006, sans trame de fermeture
          );
        });
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _silence?.cancel();
  }

  @override
  Future<void> dispose() async => disconnect();
}

final class _Bench {
  _Bench(this.async, {List<({int startMs, int endMs, String text})>? said})
    : said = said ?? mistralProbeSentences {
    server = _MistralServer(async);
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: MistralRealtimeClient(
        apiKey: () async => _key,
        transport: server.transport,
      ),
      systemClient: MistralRealtimeClient(
        apiKey: () async => _key,
        transport: _MistralServer(async).transport,
      ),
    );
    dataSource.audioGaps.listen(gaps.add);
    dataSource.transcriptionStream.listen(events.add);
    unawaited(
      dataSource.connect(systemAudioEnabled: false).catchError((Object _) {}),
    );
    async.flushMicrotasks();
  }

  static const int t0 = 1700000000000;
  final FakeAsync async;
  final List<({int startMs, int endMs, String text})> said;
  late final _MistralServer server;
  late final TranscriptionRemoteDataSourceImpl dataSource;
  final List<AudioGap> gaps = <AudioGap>[];
  final List<TranscriptEventRemoteModel> events =
      <TranscriptEventRemoteModel>[];

  bool voiced(int id) => said.any(
    (({int startMs, int endMs, String text}) s) =>
        id * 100 >= s.startMs && id * 100 < s.endMs,
  );

  /// Capture micro de [toMs] (silence compris, comme la vraie capture) ;
  /// [at] agit avant chaque chunk.
  void play(int toMs, {void Function(int id)? at}) {
    for (int id = 0; id * 100 < toMs; id++) {
      at?.call(id);
      final Uint8List data = Uint8List(3200);
      final ByteData d = ByteData.sublistView(data);
      if (voiced(id)) {
        for (int o = 4; o < data.length; o += 2) {
          d.setInt16(o, 1200, Endian.little);
        }
      }
      d
        ..setInt16(0, id & 0x7FFF, Endian.little)
        ..setInt16(2, id >> 15, Endian.little);
      dataSource.sendAudio(
        AudioChunk(
          source: AudioSource.input,
          data: data,
          timestampMs: t0 + id * 100,
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
    }
  }

  /// Arrêt : `disconnect`, puis l'attente de la fin normale.
  void stop() {
    unawaited(dataSource.disconnect());
    async.elapse(const Duration(seconds: 10));
  }

  List<TranscriptEventRemoteModel> get dones => events
      .where(
        (TranscriptEventRemoteModel e) =>
            e.type == 'response.audio_transcript.done',
      )
      .toList();

  /// Phrases ni dans un `done`, ni dans une perte signalée.
  List<String> neither() => <String>[
    for (final ({int startMs, int endMs, String text}) s in said)
      if (!dones.any(
            (TranscriptEventRemoteModel e) => (e.text ?? '').contains(s.text),
          ) &&
          !gaps.any(
            (AudioGap g) =>
                g.startMs <= t0 + s.startMs + 1000 &&
                g.endMs + 1000 >= t0 + s.endMs,
          ))
        '${s.startMs} ms « ${s.text} »',
  ];
}

void main() {
  test('ouvre l URL Mistral (modèle constant) avec la clé en Bearer ; '
      'session.update (pcm_s16le, 16 kHz, délai 80 ms) avant tout audio', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.play(5000);
      expect(MistralRealtimeClient.model, mistralProbeModel);
      expect(
        MistralRealtimeClient.url,
        'wss://api.mistral.ai/v1/audio/transcriptions/realtime'
        '?model=${MistralRealtimeClient.model}',
      );
      expect(b.server.urls.first, MistralRealtimeClient.url);
      expect(b.server.headers.first['Authorization'], 'Bearer $_key');
      final ({String type, Map<String, dynamic> json}) first =
          b.server.connections.first.sent.first;
      expect(first.type, 'session.update');
      final Map<String, dynamic> session =
          first.json['session'] as Map<String, dynamic>;
      expect(session['audio_format'], <String, Object>{
        'encoding': 'pcm_s16le',
        'sample_rate': 16000,
      });
      expect(MistralRealtimeClient.defaultStreamingDelayMs, 80);
      expect(session['target_streaming_delay_ms'], 80);
      expect(
        b.server.connections.first.sent.map(
          (({String type, Map<String, dynamic> json}) s) => s.type,
        ),
        isNot(contains('input_audio_buffer.commit')),
      );
    });
  });

  test('rejeu de la sonde : Oats fait une phrase par énoncé à partir des '
      'deltas, à sa fenêtre ; les deltas restent des deltas', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.play(mistralProbeAudioEndMs);
      async.elapse(const Duration(seconds: 5));
      expect(
        b.dones.map((TranscriptEventRemoteModel e) => e.text?.trim()),
        <String?>[
          for (final ({int startMs, int endMs, String text}) s
              in mistralProbeSentences)
            s.text,
        ],
      );
      for (int i = 0; i < b.dones.length; i++) {
        final UtteranceWindow? w = b.dataSource.windowOf(b.dones[i]);
        expect(w, isNotNull);
        expect(
          (w!.startMs - _Bench.t0 - mistralProbeSentences[i].startMs).abs(),
          lessThanOrEqualTo(1500),
          reason: 'phrase $i',
        );
      }
      expect(
        b.events.where(
          (TranscriptEventRemoteModel e) =>
              e.type == 'response.audio_transcript.delta',
        ),
        hasLength(mistralProbeDeltas.length),
      );
    });
  });

  test('arrêt : input_audio.end, done puis fermeture 1006 = fin normale : '
      'ni perte, ni reconnexion, la dernière phrase une seule fois', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.play(mistralProbeAudioEndMs);
      b.stop();
      expect(
        b.server.connections.single.sent.map(
          (({String type, Map<String, dynamic> json}) s) => s.type,
        ),
        contains('input_audio.end'),
      );
      expect(b.server.connectAttempts, hasLength(1));
      expect(b.gaps, isEmpty);
      final String last = mistralProbeSentences.last.text;
      expect(
        b.dones
            .where(
              (TranscriptEventRemoteModel e) => (e.text ?? '').contains(last),
            )
            .length,
        1,
      );
    });
  });

  for (final int pauseS in <int>[22, 40]) {
    test('pause de $pauseS s : du silence part au moins toutes les 5 s, '
        'jamais d erreur 3804', () {
      fakeAsync((FakeAsync async) {
        // La pause réelle (58,0–80,6 s), allongée au besoin.
        final int shift = (pauseS - 22) * 1000;
        final _Bench b = _Bench(
          async,
          said: <({int startMs, int endMs, String text})>[
            for (final ({int startMs, int endMs, String text}) s
                in mistralProbeSentences)
              s.startMs > 60000
                  ? (
                      startMs: s.startMs + shift,
                      endMs: s.endMs + shift,
                      text: s.text,
                    )
                  : s,
          ],
        );
        b.play(mistralProbeAudioEndMs + shift);
        expect(b.server.timeouts3804, 0);
        final List<Duration> at = b.server.connections.single.appendTimes;
        Duration worst = Duration.zero;
        for (int i = 1; i < at.length; i++) {
          if (at[i] - at[i - 1] > worst) worst = at[i] - at[i - 1];
        }
        expect(worst, lessThanOrEqualTo(const Duration(seconds: 5)));
        expect(
          MistralRealtimeClient.keepAliveEvery,
          lessThanOrEqualTo(const Duration(seconds: 5)),
        );
      });
    });
  }

  for (final String how in <String>['error 3804 puis 1011', 'réseau coupé']) {
    test('$how en pleine phrase : reconnexion ; chaque phrase dans un done ou '
        'sous une perte signalée', () {
      fakeAsync((FakeAsync async) {
        final _Bench b = _Bench(async);
        b.play(
          mistralProbeAudioEndMs,
          at: (int id) {
            if (id == 330 || id == 450) {
              final _MistralSocket? s = _liveSocket(b);
              if (how.startsWith('error')) {
                s?.fail3804();
              } else {
                s?.close();
              }
            }
          },
        );
        b.stop();
        expect(b.server.connectAttempts.length, greaterThanOrEqualTo(2));
        expect(b.neither(), isEmpty, reason: b.neither().join('\n'));
      });
    });
  }

  test('clé refusée (401) : pas de tempête de reconnexions', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.server.refuseKey = true;
      _liveSocket(b)?.close();
      b.play(600000); // 10 min
      expect(
        b.server.connectAttempts.length,
        lessThanOrEqualTo(3),
        reason: 'tentatives à ${b.server.connectAttempts}',
      );
    });
  });

  // Revue PR #33 : un delta qui arrive APRÈS le `done` de sa phrase (rendu
  // 500 ms après le delta précédent) ne doit pas disparaître en silence.
  test('delta tardif après le done de la phrase, puis arrêt : ses mots sont '
      'dans un done ou sous une perte signalée', () {
    fakeAsync((FakeAsync async) {
      final ({int startMs, int endMs, String text}) s0 =
          mistralProbeSentences.first;
      final _Bench b = _Bench(
        async,
        said: <({int startMs, int endMs, String text})>[s0],
      );
      b.play(9000);
      expect(b.dones, hasLength(1), reason: 'le done de la phrase est parti');
      expect(b.dones.single.text, isNot(contains('TARDIF')));

      _liveSocket(b)!.push(<String, Object?>{
        'type': 'transcription.text.delta',
        'text': ' TARDIF',
      });
      async.elapse(const Duration(seconds: 1));
      b.stop();

      final bool inDone = b.dones.any(
        (TranscriptEventRemoteModel e) => (e.text ?? '').contains('TARDIF'),
      );
      final bool underGap = b.gaps.any(
        (AudioGap g) =>
            g.startMs <= _Bench.t0 + s0.startMs + 1000 &&
            g.endMs + 1000 >= _Bench.t0 + s0.endMs,
      );
      expect(
        inDone || underGap,
        isTrue,
        reason:
            'dones ${b.dones.map((TranscriptEventRemoteModel e) => e.text)}, '
            'pertes ${b.gaps.length}',
      );
    });
  });

  test('delta tardif de la phrase 1, puis la phrase 2 : chaque done garde la '
      'fenêtre de sa propre phrase', () {
    fakeAsync((FakeAsync async) {
      final List<({int startMs, int endMs, String text})> said =
          mistralProbeSentences.take(2).toList();
      final _Bench b = _Bench(async, said: said);
      b.play(
        17000,
        at: (int id) {
          // 8,6 s : le done de la phrase 1 est parti, la phrase 2 (8,71 s)
          // pas encore commencée.
          if (id != 86) return;
          expect(b.dones, hasLength(1));
          _liveSocket(b)!.push(<String, Object?>{
            'type': 'transcription.text.delta',
            'text': ' TARDIF',
          });
        },
      );
      async.elapse(const Duration(seconds: 5));

      for (final ({int startMs, int endMs, String text}) s in said) {
        final TranscriptEventRemoteModel done = b.dones.singleWhere(
          (TranscriptEventRemoteModel e) => (e.text ?? '').contains(s.text),
        );
        final UtteranceWindow? w = b.dataSource.windowOf(done);
        expect(w, isNotNull, reason: s.text);
        expect(
          (w!.startMs - _Bench.t0 - s.startMs).abs(),
          lessThanOrEqualTo(1500),
          reason: 'fenêtre de « ${s.text} »',
        );
      }
      expect(
        b.dones.any(
          (TranscriptEventRemoteModel e) => (e.text ?? '').contains('TARDIF'),
        ),
        isTrue,
      );
    });
  });

  test('la clé n apparaît jamais dans les journaux', () async {
    final Directory dir = await Directory.systemTemp.createTemp('oats_log_');
    final String path = '${dir.path}/oats.log';
    Log.writeToFile(path);
    bool sawKey = false;
    final MistralRealtimeClient client = MistralRealtimeClient(
      apiKey: () async => _key,
      transport: (Map<String, String> headers) {
        sawKey = headers.values.any((String v) => v.contains(_key));
        return _EchoSocket(headers);
      },
    );
    await client
        .connect('ws://localhost:8000/v1/realtime')
        .catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final String log = File(path).existsSync()
        ? File(path).readAsStringSync()
        : '';
    await dir.delete(recursive: true);
    expect(log.contains(_key), isFalse);
    expect(sawKey, isTrue, reason: 'le transport a bien reçu la clé');
  });
}

/// Socket vivante du micro (la dernière créée par le transport).
_MistralSocket? _liveSocket(_Bench b) => b.server.sockets.lastOrNull;

/// Transport dont l'échec recopie ses en-têtes dans le message d'erreur
/// (trace HTTP verbeuse) : le client ne doit pas le journaliser tel quel.
final class _EchoSocket extends WebSocketClient {
  _EchoSocket(this._headers);

  final Map<String, String> _headers;

  @override
  Future<void> connect(String url) async =>
      throw WebSocketException('refused, request headers: $_headers');
}
