import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

/// Moteur de transcription EN LIGNE : Mistral Voxtral temps réel, sous la
/// couche de fiabilité existante (tampon non acquitté, fenêtres, pertes,
/// reconnexion à borne adaptative, attente à l'arrêt) qui reste INCHANGÉE.
///
/// API supposée : `MistralRealtimeClient extends WebSocketClient`
/// (`package:core_data/clients/mistral_realtime_client.dart`) :
/// `MistralRealtimeClient({required apiKey, required transport,
/// int targetStreamingDelayMs, String? language})` : `apiKey` rend la clé
/// (lue à chaque connexion, peut être nulle) ; `transport` crée la socket
/// brute à partir des en-têtes HTTP à envoyer ;
/// `static const String model` (temps réel : `voxtral-mini-transcribe-
/// realtime-3-0`, listé par le compte ; 2602 aussi) et `static const String
/// url` ; `MistralKeyRejected implements Exception`. La clé est au
/// trousseau, compte `mistral` (`LlmProviderId.mistral`).
/// Le client parle notre protocole (celui de voxmlx) à
/// `TranscriptionRemoteDataSourceImpl` et le protocole Mistral au
/// transport.
///
/// CORRESPONDANCE CHOISIE (protocole mistralai/client-python, main) :
/// - `connect(url)` ignore l'URL locale : ouvre [MistralRealtimeClient.url]
///   (`wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=` +
///   modèle) avec l'en-tête `Authorization: Bearer` + clé (lue à chaque
///   connexion) ; premier message `session.update`
///   (`audio_format` pcm_s16le / 16000, `target_streaming_delay_ms`) avant
///   tout audio ; connecté une fois `session.updated` reçu (la poignée de
///   main reste sous la borne adaptative du client) ;
/// - `input_audio_buffer.append` → `input_audio.append`, même base64 (nos
///   chunks de 100 ms font 3 200 octets, bien sous 262 144) ;
/// - commit final d'une phrase (`input_audio_buffer.commit` final) →
///   `input_audio.flush` ; jamais de commit façon OpenAI ;
/// - `transcription.text.delta` {text} → `response.audio_transcript.delta`
///   {delta} ;
/// - `transcription.segment` {text, start, end} : rangés ; UN
///   `response.audio_transcript.done` par flush, texte = segments de ce
///   flush mis bout à bout, émis dès qu'un segment finit à 1,5 s près de la
///   fin de l'audio vidé (temps du flux : octets envoyés depuis la
///   connexion / 32 000) ou qu'un segment commence après elle (flush sans
///   parole : `done` vide) ; `transcription.done` ferme tous les flushs en
///   attente ;
/// - `error` → coupure (socket fermée, `onClosed`) : la couche de fiabilité
///   reconnecte et renvoie ; socket fermée → idem ;
/// - clé refusée (poignée de main HTTP 401, ou `error` 401 / clé invalide)
///   → `MistralKeyRejected` : pas de tempête de reconnexions.
const String _key = 'mistral-test-SECRET-0123456789';

final class _Sent {
  _Sent(this.type, this.json);
  final String type;
  final Map<String, dynamic> json;
}

/// Serveur Mistral factice (une connexion par transport créé).
final class _MistralServer {
  _MistralServer(this.async);

  final FakeAsync async;
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<String> urls = <String>[];
  final List<List<_Sent>> sessions = <List<_Sent>>[];
  final Set<int> transcribedIds = <int>{};
  final List<Duration> connectAttempts = <Duration>[];
  bool refuseKey = false;
  bool accepting = true;
  int segmentsPerFlush = 1;
  Duration answerAfter = const Duration(milliseconds: 400);
  _MistralSocket? live;

  WebSocketClient transport(Map<String, String> h) {
    headers.add(Map<String, String>.of(h));
    return _MistralSocket(this);
  }
}

final class _MistralSocket extends WebSocketClient {
  _MistralSocket(this._server);

  final _MistralServer _server;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<void> _closed = StreamController<void>.broadcast();
  bool _connected = false;
  late List<_Sent> _log;
  int _bytes = 0;
  int _flushedBytes = 0;
  List<int> _ids = <int>[];

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  void push(Map<String, Object?> event) {
    if (_connected) _messages.add(jsonEncode(event));
  }

  void drop() {
    if (!_connected) return;
    _connected = false;
    _closed.add(null);
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
    if (!_server.accepting) {
      throw const SocketException('Connection refused');
    }
    _connected = true;
    _log = <_Sent>[];
    _server.sessions.add(_log);
    _server.live = this;
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
    _log.add(_Sent(type, json));
    switch (type) {
      case 'session.update':
        scheduleMicrotask(
          () => push(<String, Object?>{
            'type': 'session.updated',
            'session': json['session'],
          }),
        );
      case 'input_audio.append':
        final Uint8List audio = base64Decode(json['audio'] as String);
        final ByteData d = ByteData.sublistView(audio);
        _ids.add(
          d.getInt16(0, Endian.little) + (d.getInt16(2, Endian.little) << 15),
        );
        _bytes += audio.length;
      case 'input_audio.flush':
        final List<int> ids = _ids;
        _ids = <int>[];
        final double start = _flushedBytes / 32000;
        final double end = _bytes / 32000;
        _flushedBytes = _bytes;
        final int n = _server.segmentsPerFlush;
        Timer(_server.answerAfter, () {
          if (!_connected) return;
          push(<String, Object?>{
            'type': 'transcription.text.delta',
            'text': 'phrase ',
          });
          for (int k = 0; k < n; k++) {
            final double a = start + (end - start - 1.2) * k / n;
            final double b = start + (end - start - 1.2) * (k + 1) / n;
            push(<String, Object?>{
              'type': 'transcription.segment',
              'text': 'Morceau ${ids.first}-$k.',
              'start': a,
              'end': b,
            });
          }
          _server.transcribedIds.addAll(ids);
        });
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
  }
}

AudioChunk _chunk(AudioSource source, int id, int t0, {required bool voiced}) {
  final Uint8List data = Uint8List(3200);
  final ByteData d = ByteData.sublistView(data);
  if (voiced) {
    for (int o = 4; o < data.length; o += 2) {
      d.setInt16(o, 1200, Endian.little);
    }
  }
  d
    ..setInt16(0, id & 0x7FFF, Endian.little)
    ..setInt16(2, id >> 15, Endian.little);
  return AudioChunk(source: source, data: data, timestampMs: t0 + id * 100);
}

final class _Bench {
  _Bench(this.async) {
    mic = _MistralServer(async);
    sys = _MistralServer(async);
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: MistralRealtimeClient(
        apiKey: () async => _key,
        transport: mic.transport,
      ),
      systemClient: MistralRealtimeClient(
        apiKey: () async => _key,
        transport: sys.transport,
      ),
    );
    dataSource.audioGaps.listen(gaps.add);
    dataSource.transcriptionStream.listen(micEvents.add);
    unawaited(
      dataSource.connect(systemAudioEnabled: false).catchError((Object _) {}),
    );
    async.flushMicrotasks();
  }

  static const int t0 = 1700000000000;
  final FakeAsync async;
  late final _MistralServer mic;
  late final _MistralServer sys;
  late final TranscriptionRemoteDataSourceImpl dataSource;
  final List<AudioGap> gaps = <AudioGap>[];
  final List<TranscriptEventRemoteModel> micEvents =
      <TranscriptEventRemoteModel>[];
  final List<int> voicedIds = <int>[];

  /// Phrases de 7,5 s, 2,5 s de pause, [seconds] s à partir de [fromId].
  int speak(int fromId, int seconds, {void Function(int id)? at}) {
    int id = fromId;
    for (; id < fromId + seconds * 10; id++) {
      at?.call(id);
      final bool v = id % 100 < 75;
      if (v) voicedIds.add(id);
      dataSource.sendAudio(_chunk(AudioSource.input, id, t0, voiced: v));
      async.elapse(const Duration(milliseconds: 100));
    }
    return id;
  }

  bool inGap(int id) => gaps.any(
    (AudioGap g) =>
        g.source == AudioSource.input &&
        t0 + id * 100 >= g.startMs &&
        t0 + id * 100 < g.endMs,
  );

  List<TranscriptEventRemoteModel> get dones => micEvents
      .where(
        (TranscriptEventRemoteModel e) =>
            e.type == 'response.audio_transcript.done',
      )
      .toList();
}

void main() {
  test('ouvre l URL Mistral avec la clé en Bearer ; session.update '
      '(pcm_s16le, 16 kHz, délai) avant tout audio', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.speak(0, 10);

      expect(b.mic.urls.first, MistralRealtimeClient.url);
      // Un seul modèle temps réel, en constante (compte vérifié : listé).
      expect(
        MistralRealtimeClient.model,
        'voxtral-mini-transcribe-realtime-3-0',
      );
      expect(
        MistralRealtimeClient.url,
        'wss://api.mistral.ai/v1/audio/transcriptions/realtime'
        '?model=${MistralRealtimeClient.model}',
      );
      expect(b.mic.headers.first['Authorization'], 'Bearer $_key');
      final List<_Sent> sent = b.mic.sessions.first;
      expect(sent.first.type, 'session.update');
      final Map<String, dynamic> session =
          sent.first.json['session'] as Map<String, dynamic>;
      expect(session['audio_format'], <String, Object>{
        'encoding': 'pcm_s16le',
        'sample_rate': 16000,
      });
      expect(session['target_streaming_delay_ms'], isA<int>());
    });
  });

  test('audio → input_audio.append (même PCM, ≤ 262 144 octets), fin de '
      'phrase → input_audio.flush, jamais de commit OpenAI', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.speak(0, 30);
      final List<_Sent> sent = b.mic.sessions.first;
      final Iterable<String> types = sent.map((_Sent s) => s.type);
      expect(types, isNot(contains('input_audio_buffer.append')));
      expect(types, isNot(contains('input_audio_buffer.commit')));
      expect(types.where((String t) => t == 'input_audio.flush').length, 3);
      for (final _Sent s in sent.where(
        (_Sent s) => s.type == 'input_audio.append',
      )) {
        expect(
          base64Decode(s.json['audio'] as String).length,
          lessThanOrEqualTo(262144),
        );
      }
      // Chaque chunk voisé est arrivé tel quel, dans l'ordre.
      expect(b.mic.transcribedIds.toList()..sort(), b.voicedIds);
    });
  });

  test('un transcription.segment par phrase : un done par fenêtre, à la '
      'fenêtre de sa phrase ; les deltas restent des deltas', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.speak(0, 30);
      async.elapse(const Duration(seconds: 5));
      final List<TranscriptEventRemoteModel> dones = b.dones;
      expect(dones.map((TranscriptEventRemoteModel e) => e.text), <String>[
        'Morceau 0-0.',
        'Morceau 100-0.',
        'Morceau 200-0.',
      ]);
      for (int i = 0; i < 3; i++) {
        final UtteranceWindow? w = b.dataSource.windowOf(dones[i]);
        expect(w, isNotNull);
        expect(w!.startMs, _Bench.t0 + i * 10000);
      }
      expect(
        b.micEvents.where(
          (TranscriptEventRemoteModel e) =>
              e.type == 'response.audio_transcript.delta',
        ),
        isNotEmpty,
      );
    });
  });

  test('deux segments pour une phrase : un seul done, texte des deux', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.mic.segmentsPerFlush = 2;
      b.speak(0, 20);
      async.elapse(const Duration(seconds: 5));
      expect(b.dones.map((TranscriptEventRemoteModel e) => e.text), <String>[
        'Morceau 0-0. Morceau 0-1.',
        'Morceau 100-0. Morceau 100-1.',
      ]);
    });
  });

  for (final String how in <String>['error', 'socket fermée']) {
    test('$how en pleine phrase : coupure, reconnexion, renvoi ; chaque '
        'chunk voisé transcrit ou sous une perte signalée', () {
      fakeAsync((FakeAsync async) {
        final _Bench b = _Bench(async);
        b.speak(
          0,
          60,
          at: (int id) {
            if (id == 230 || id == 410) {
              if (how == 'error') {
                b.mic.live!.push(<String, Object?>{
                  'type': 'error',
                  'error': <String, Object?>{
                    'message': 'internal error',
                    'code': 500,
                  },
                });
              } else {
                b.mic.live!.drop();
              }
            }
          },
        );
        unawaited(b.dataSource.disconnect());
        async.elapse(const Duration(minutes: 2));

        expect(b.mic.sessions.length, greaterThanOrEqualTo(3));
        final List<int> silent = <int>[
          for (final int id in b.voicedIds)
            if (!b.mic.transcribedIds.contains(id) && !b.inGap(id)) id,
        ];
        expect(silent, isEmpty, reason: '${silent.length} chunks perdus');
      });
    });
  }

  test('clé refusée (401) : pas de tempête de reconnexions', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.mic.refuseKey = true;
      b.mic.live!.drop();
      b.speak(0, 600); // 10 min
      expect(
        b.mic.connectAttempts.length,
        lessThanOrEqualTo(3),
        reason: 'tentatives à ${b.mic.connectAttempts}',
      );
    });
  });

  test('`error` clé invalide en cours de séance : pas de tempête non plus', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.speak(0, 5);
      b.mic.refuseKey = true;
      b.mic.live!.push(<String, Object?>{
        'type': 'error',
        'error': <String, Object?>{'message': 'Unauthorized', 'code': 401},
      });
      b.speak(50, 600);
      expect(b.mic.connectAttempts.length, lessThanOrEqualTo(4));
    });
  });

  test('propriété : coupures répétées pendant 10 min, rien perdu en '
      'silence, rien transcrit deux fois', () {
    fakeAsync((FakeAsync async) {
      final _Bench b = _Bench(async);
      b.speak(
        0,
        600,
        at: (int id) {
          if (id % 1300 == 700) b.mic.live?.drop();
          if (id % 1300 == 710) b.mic.accepting = false;
          if (id % 1300 == 1000) b.mic.accepting = true;
        },
      );
      unawaited(b.dataSource.disconnect());
      async.elapse(const Duration(minutes: 3));
      final List<int> silent = <int>[
        for (final int id in b.voicedIds)
          if (!b.mic.transcribedIds.contains(id) && !b.inGap(id)) id,
      ];
      expect(silent, isEmpty, reason: '${silent.length} chunks perdus');
    });
  });

  test('la clé n apparaît jamais dans les journaux', () async {
    final Directory dir = await Directory.systemTemp.createTemp('oats_log_');
    final String path = '${dir.path}/oats.log';
    Log.writeToFile(path);
    final _Echo echo = _Echo();
    final MistralRealtimeClient client = MistralRealtimeClient(
      apiKey: () async => _key,
      transport: echo.transport,
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
    expect(echo.sawKey, isTrue, reason: 'le transport a bien reçu la clé');
  });
}

/// Transport dont l'échec recopie ses en-têtes dans le message d'erreur
/// (comme une trace HTTP verbeuse) : le client ne doit pas le journaliser
/// tel quel.
final class _Echo {
  bool sawKey = false;

  WebSocketClient transport(Map<String, String> headers) {
    sawKey = headers.values.any((String v) => v.contains(_key));
    return _EchoSocket(headers);
  }
}

final class _EchoSocket extends WebSocketClient {
  _EchoSocket(this._headers);

  final Map<String, String> _headers;

  @override
  Future<void> connect(String url) async =>
      throw WebSocketException('refused, request headers: $_headers');
}
