import 'dart:async';
import 'dart:io';

import 'package:core_data/clients/websocket_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Tour 5, points 1 et 4, sur le vrai [WebSocketClient] (canal factice par
/// sa fabrique) : il annonce une fermeture côté serveur par `onClosed`
/// (API supposée, `Stream<void>`), pas une déconnexion demandée ; et une
/// poignée de main qui ne finit jamais fait échouer `connect` en 10 s.
void main() {
  test('la fin du canal côté serveur est annoncée', () async {
    final _Channel channel = _Channel();
    final WebSocketClient client = WebSocketClient(
      connectChannel: (_) => channel,
    );
    await client.connect('ws://test');
    final Future<void> closed = client.onClosed.first;

    channel.closeFromServer();

    await closed.timeout(const Duration(seconds: 1));
    expect(client.isConnected, isFalse);
  });

  test('une erreur du canal est annoncée comme une fermeture', () async {
    final _Channel channel = _Channel();
    final WebSocketClient client = WebSocketClient(
      connectChannel: (_) => channel,
    );
    client.messageStream.listen((_) {}, onError: (_) {});
    await client.connect('ws://test');
    final Future<void> closed = client.onClosed.first;

    channel.failFromServer();

    await closed.timeout(const Duration(seconds: 1));
    expect(client.isConnected, isFalse);
  });

  test('une déconnexion demandée n est pas une fermeture serveur', () async {
    final WebSocketClient client = WebSocketClient(
      connectChannel: (_) => _Channel(),
    );
    await client.connect('ws://test');
    int closes = 0;
    client.onClosed.listen((_) => closes++);

    await client.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(closes, 0);
  });

  test('une poignée de main sans fin fait échouer connect en 10 s', () {
    fakeAsync((FakeAsync async) {
      final WebSocketClient client = WebSocketClient(
        connectChannel: (_) => _Channel(ready: Completer<void>().future),
      );
      Object? outcome;
      client
          .connect('ws://test')
          .then((_) => outcome = 'ok', onError: (Object e) => outcome = e);
      async.elapse(const Duration(seconds: 11));

      expect(outcome, isNotNull);
      expect(outcome, isNot('ok'));
      expect(client.isConnected, isFalse);
    });
  });
}

final class _Channel implements WebSocketChannel {
  _Channel({Future<void>? ready}) : ready = ready ?? Future<void>.value();

  final StreamController<dynamic> _fromServer = StreamController<dynamic>();

  @override
  final Future<void> ready;

  @override
  Stream<dynamic> get stream => _fromServer.stream;

  @override
  WebSocketSink get sink => _Sink();

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sink implements WebSocketSink {
  @override
  void add(Object? message) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
