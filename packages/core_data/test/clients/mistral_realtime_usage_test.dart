import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/engine_routing_client.dart';
import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// Prix de la transcription en ligne (besoin du 2026-11-26) : Mistral
/// facture l'audio réellement envoyé (sonde : 900 appends de 100 ms →
/// `usage.prompt_audio_seconds` = 90). Le client temps réel compte donc
/// l'audio de chaque `input_audio.append` qu'il écrit sur la socket :
/// l'audio de la réunion, le silence de maintien (100 ms toutes les 4 s de
/// calme), l'audio renvoyé après une reconnexion. Rien n'est compté quand
/// l'envoi est jeté (pas connecté).
///
/// API supposée :
/// - `int WebSocketClient.takeSentAudioMs()` : ms d'audio envoyées depuis
///   le dernier appel, puis remise à zéro. La classe de base rend toujours
///   0 (voxmlx local n'est pas facturé) ;
/// - `MistralRealtimeClient.takeSentAudioMs()` : somme des
///   `input_audio.append` écrits sur la socket brute (octets PCM16 / 32 =
///   ms à 16 kHz mono), maintien compris. `connect()` (reconnexion) ne remet
///   PAS le compte à zéro : seul `takeSentAudioMs()` le fait ;
/// - `EngineRoutingClient.takeSentAudioMs()` : celui de son client Mistral ;
/// - `TranscriptionRemoteDataSource.takeSentAudioMs()` : somme des deux
///   sockets (micro + système), remises à zéro toutes les deux.
///
/// Oracle : l'audio que le faux serveur a reçu (base64 décodé / 32).
const String _key = 'mistral-test-SECRET-0123456789';

/// Faux service Mistral : compte l'audio reçu par `input_audio.append`.
final class _Server {
  int appendedBytes = 0;
  int appends = 0;
  final List<_Socket> sockets = <_Socket>[];

  int get appendedMs => appendedBytes ~/ 32;

  _Socket get live => sockets.last;

  WebSocketClient transport(Map<String, String> headers) {
    final _Socket s = _Socket(this);
    sockets.add(s);
    return s;
  }
}

final class _Socket extends WebSocketClient {
  _Socket(this._server);

  final _Server _server;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<void> _closed = StreamController<void>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  /// Coupure réseau ou fermeture côté serveur.
  void drop() {
    if (!_connected) return;
    _connected = false;
    _closed.add(null);
  }

  @override
  Future<void> connect(String url) async => _connected = true;

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    switch (json['type']) {
      case 'session.update':
        scheduleMicrotask(() {
          if (_connected) {
            _messages.add(
              jsonEncode(<String, Object>{
                'type': 'session.updated',
                'session': <String, Object>{},
              }),
            );
          }
        });
      case 'input_audio.append':
        _server.appends++;
        _server.appendedBytes += base64Decode(json['audio'] as String).length;
    }
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> dispose() async => _connected = false;
}

/// Socket « locale » (voxmlx) : accepte tout, ne répond rien.
final class _LocalSocket extends WebSocketClient {
  bool _connected = false;
  int sent = 0;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => const Stream<String>.empty();

  @override
  Stream<void> get onClosed => const Stream<void>.empty();

  @override
  Future<void> connect(String url) async => _connected = true;

  @override
  void send(String message) {
    if (_connected) sent++;
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> dispose() async => _connected = false;
}

MistralRealtimeClient _client(_Server server) => MistralRealtimeClient(
  apiKey: () async => _key,
  transport: server.transport,
);

/// Ce que la source distante envoie pour [ms] d'audio (PCM16 mono 16 kHz).
String _append(int ms) => jsonEncode(<String, String>{
  'type': 'input_audio_buffer.append',
  'audio': base64Encode(Uint8List(ms * 32)),
});

void _connect(FakeAsync async, WebSocketClient client) {
  unawaited(client.connect(MistralRealtimeClient.url));
  async.flushMicrotasks();
  expect(client.isConnected, isTrue, reason: 'connexion du faux Mistral');
}

/// Chunk micro ou système de 100 ms, voisé (au-dessus du seuil de parole).
AudioChunk _voiced(AudioSource source, int id) {
  final Uint8List data = Uint8List(3200);
  final ByteData d = ByteData.sublistView(data);
  for (int o = 0; o < data.length; o += 2) {
    d.setInt16(o, 1200, Endian.little);
  }
  return AudioChunk(
    source: source,
    data: data,
    timestampMs: 1700000000000 + id * 100,
  );
}

void main() {
  group('MistralRealtimeClient compte l audio mis sur la socket', () {
    test('chaque append compte pour sa durée réelle (octets), y compris un '
        'chunk qui ne fait pas 100 ms ; un commit ne compte pas', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        _connect(async, client);

        for (int i = 0; i < 10; i++) {
          client.send(_append(100));
        }
        client
          ..send(_append(150))
          ..send(_append(37))
          ..send(
            jsonEncode(<String, Object>{
              'type': 'input_audio_buffer.commit',
              'final': true,
            }),
          );

        expect(server.appendedMs, 1187, reason: 'oracle : audio reçu');
        expect(client.takeSentAudioMs(), 1187);
      });
    });

    test('le silence de maintien (pause sans parole) est compté : il part '
        'sur la socket et Mistral le facture', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        _connect(async, client);

        async.elapse(const Duration(seconds: 13));

        expect(server.appends, greaterThanOrEqualTo(2), reason: 'maintien');
        expect(server.appendedMs, greaterThan(0));
        expect(client.takeSentAudioMs(), server.appendedMs);
      });
    });

    test('après une coupure et une reconnexion, l audio envoyé avant et '
        'après s additionne (la reconnexion ne remet pas à zéro)', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        _connect(async, client);
        for (int i = 0; i < 10; i++) {
          client.send(_append(100));
        }

        server.live.drop();
        async.flushMicrotasks();
        _connect(async, client);
        for (int i = 0; i < 5; i++) {
          client.send(_append(100));
        }

        expect(server.sockets, hasLength(2), reason: 'deux sockets');
        expect(server.appendedMs, 1500);
        expect(client.takeSentAudioMs(), 1500);
      });
    });

    test('un envoi jeté (avant la connexion, ou socket coupée) ne compte '
        'pas', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        client.send(_append(100)); // pas encore connecté
        expect(client.takeSentAudioMs(), 0);

        _connect(async, client);
        client
          ..send(_append(100))
          ..send(_append(100));
        server.live.drop();
        async.flushMicrotasks();
        for (int i = 0; i < 3; i++) {
          client.send(_append(100)); // coupé : jeté
        }

        expect(server.appendedMs, 200);
        expect(client.takeSentAudioMs(), 200);
      });
    });

    test('la lecture remet à zéro : la réunion suivante repart de zéro', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        _connect(async, client);
        for (int i = 0; i < 4; i++) {
          client.send(_append(100));
        }
        expect(client.takeSentAudioMs(), 400);
        expect(client.takeSentAudioMs(), 0, reason: 'déjà lu');

        client
          ..send(_append(100))
          ..send(_append(100));
        expect(client.takeSentAudioMs(), 200);
      });
    });

    test('l arrêt (input_audio.end, attente du done) n ajoute pas d audio', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final MistralRealtimeClient client = _client(server);
        _connect(async, client);
        for (int i = 0; i < 5; i++) {
          client.send(_append(100));
        }

        unawaited(client.disconnect());
        async.elapse(const Duration(seconds: 10));

        expect(server.appendedMs, 500);
        expect(client.takeSentAudioMs(), 500);
      });
    });
  });

  group('routage et source distante', () {
    test('un client voxmlx (classe de base) n est jamais facturé', () {
      expect(WebSocketClient().takeSentAudioMs(), 0);
    });

    test('EngineRoutingClient routé vers Mistral : le compte de son client '
        'Mistral', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final EngineRoutingClient routed = EngineRoutingClient(
          local: _LocalSocket(),
          mistral: _client(server),
        );
        _connect(async, routed);
        for (int i = 0; i < 5; i++) {
          routed.send(_append(100));
        }
        expect(server.appendedMs, 500);
        expect(routed.takeSentAudioMs(), 500);
      });
    });

    test('EngineRoutingClient routé en local (après une séance Mistral lue) : '
        'rien', () {
      fakeAsync((FakeAsync async) {
        final _Server server = _Server();
        final _LocalSocket local = _LocalSocket();
        final EngineRoutingClient routed = EngineRoutingClient(
          local: local,
          mistral: _client(server),
        );
        _connect(async, routed);
        routed.send(_append(100));
        routed.takeSentAudioMs();

        unawaited(routed.connect('ws://voxmlx.test/v1/realtime'));
        async.elapse(const Duration(seconds: 5));
        for (int i = 0; i < 5; i++) {
          routed.send(_append(100));
        }
        expect(local.sent, greaterThanOrEqualTo(5), reason: 'routé en local');
        expect(server.appendedMs, 100, reason: 'rien de plus chez Mistral');
        expect(routed.takeSentAudioMs(), 0);
      });
    });

    test('deux sources (micro + son du Mac) = deux sockets : le total de la '
        'séance est la somme des deux, puis repart de zéro', () {
      fakeAsync((FakeAsync async) {
        final _Server mic = _Server();
        final _Server system = _Server();
        final TranscriptionRemoteDataSourceImpl ds =
            TranscriptionRemoteDataSourceImpl(
              micClient: EngineRoutingClient(
                local: _LocalSocket(),
                mistral: _client(mic),
              ),
              systemClient: EngineRoutingClient(
                local: _LocalSocket(),
                mistral: _client(system),
              ),
            );
        unawaited(
          ds.connect(url: MistralRealtimeClient.url).catchError((Object _) {}),
        );
        async.flushMicrotasks();

        for (int id = 0; id < 30; id++) {
          if (id < 20) ds.sendAudio(_voiced(AudioSource.input, id));
          ds.sendAudio(_voiced(AudioSource.output, id));
          async.elapse(const Duration(milliseconds: 100));
        }

        expect(mic.appendedMs, greaterThan(0), reason: 'micro envoyé');
        expect(system.appendedMs, greaterThan(0), reason: 'système envoyé');
        expect(ds.takeSentAudioMs(), mic.appendedMs + system.appendedMs);
        expect(ds.takeSentAudioMs(), 0, reason: 'déjà lu');
      });
    });
  });
}
