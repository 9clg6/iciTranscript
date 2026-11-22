import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../helpers/fake_websocket_client.dart' show chunk, chunkIdOf;

/// Tour 2, point 3 : le vrai [WebSocketClient], branché sur un canal factice
/// par sa fabrique injectable, derrière la vraie source distante : la
/// fermeture de la socket est vue, le tampon part dans l'ordre et sans
/// doublon sur la nouvelle socket, les états passent par la coupure.
///
/// Temps réel, pas fake_async : `disconnect()` attend `cancel()` d'un
/// abonnement fini, dont le futur vit dans la zone racine et ne se résout
/// jamais sous fake_async (vérifié). Le plafond de 10 s et la croissance du
/// délai sont spécifiés sur la source distante
/// (transcription_remote_data_source_reconnect_test.dart) : ici on n'attend
/// que les premières tentatives (0,5 s puis 1 s).
void main() {
  const int t0 = 1700000000000;

  late _FakeServer server;
  late TranscriptionRemoteDataSourceImpl dataSource;
  late List<domain.ConnectionState> states;

  setUp(() async {
    server = _FakeServer();
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: WebSocketClient(connectChannel: server.connect),
      systemClient: WebSocketClient(connectChannel: server.connect),
    );
    states = <domain.ConnectionState>[];
    dataSource.connectionState.listen(states.add);
    await dataSource.connect(systemAudioEnabled: false);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => dataSource.dispose());

  void feed(int fromId, int count) {
    for (int id = fromId; id < fromId + count; id++) {
      dataSource.sendAudio(
        chunk(AudioSource.input, id, timestampMs: t0 + id * 100),
      );
    }
  }

  /// Attend (temps réel, 8 s au plus) que [condition] soit vraie.
  Future<void> eventually(bool Function() condition) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!condition() && watch.elapsed < const Duration(seconds: 8)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  List<int> range(int from, int toExclusive) =>
      List<int>.generate(toExclusive - from, (int i) => from + i);

  test('la fermeture de la socket par le serveur est vue et rattrapée, '
      'tampon dans l ordre puis audio en direct', () async {
    expect(server.channels, hasLength(1));
    expect(states.last, domain.ConnectionState.connected);

    server.channels.last.closeFromServer();
    await Future<void>.delayed(Duration.zero);
    feed(0, 50);
    await Future<void>.delayed(Duration.zero);
    expect(server.channels.first.receivedIds, isEmpty);
    expect(states.last, isNot(domain.ConnectionState.connected));

    await eventually(() => server.channels.last.receivedIds.length >= 50);
    feed(50, 10);
    await Future<void>.delayed(Duration.zero);

    expect(server.channels, hasLength(2));
    expect(server.channels.last.receivedIds, range(0, 60));
    expect(states.last, domain.ConnectionState.connected);
  });

  test('une erreur du canal est traitée comme une coupure', () async {
    server.channels.last.failFromServer();
    await Future<void>.delayed(Duration.zero);
    feed(0, 20);

    await eventually(() => server.channels.last.receivedIds.length >= 20);

    expect(server.channels, hasLength(2));
    expect(server.channels.last.receivedIds, range(0, 20));
  });

  test('un canal refusé ne reçoit rien, le suivant reçoit tout une seule '
      'fois', () async {
    server.accepting = false;
    server.channels.last.closeFromServer();
    await Future<void>.delayed(Duration.zero);
    feed(0, 30);

    await eventually(() => server.channels.length >= 2);
    server.accepting = true;
    await eventually(() => server.channels.last.receivedIds.length >= 30);
    await Future<void>.delayed(Duration.zero);

    final Iterable<_FakeChannel> refused = server.channels.where(
      (_FakeChannel c) => !c.accepted,
    );
    expect(refused, isNotEmpty);
    for (final _FakeChannel channel in refused) {
      expect(channel.receivedIds, isEmpty);
    }
    expect(server.channels.last.receivedIds, range(0, 30));
    expect(states.last, domain.ConnectionState.connected);
  });
}

/// Serveur factice : ouvre un canal par connexion, accepte ou refuse.
final class _FakeServer {
  bool accepting = true;
  final List<_FakeChannel> channels = <_FakeChannel>[];

  WebSocketChannel connect(Uri uri) {
    final _FakeChannel channel = _FakeChannel(accepted: accepting);
    channels.add(channel);
    return channel;
  }
}

/// Canal sans réseau. `noSuchMethod` couvre les membres de StreamChannel
/// que le client n'utilise pas.
final class _FakeChannel implements WebSocketChannel {
  _FakeChannel({required this.accepted})
    : ready = accepted
          ? Future<void>.value()
          : Future<void>.error(const SocketException('Connection refused'));

  final bool accepted;
  final StreamController<dynamic> _fromServer = StreamController<dynamic>();
  late final _FakeSink _sink = _FakeSink(this);
  final List<int> receivedIds = <int>[];

  @override
  final Future<void> ready;

  @override
  Stream<dynamic> get stream => _fromServer.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  void closeFromServer() => unawaited(_fromServer.close());

  void failFromServer() {
    _fromServer.addError(const SocketException('Connection reset by peer'));
    unawaited(_fromServer.close());
  }

  void _receive(Object? message) {
    final Map<String, dynamic> json =
        jsonDecode(message! as String) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      receivedIds.add(chunkIdOf(json['audio'] as String));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;
  bool _closed = false;

  @override
  void add(Object? message) {
    if (_closed) throw StateError('Cannot add to a closed sink');
    _channel._receive(message);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _closed = true;
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
