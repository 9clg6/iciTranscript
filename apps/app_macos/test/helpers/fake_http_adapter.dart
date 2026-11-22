import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Transport HTTP factice pour Dio : aucun appel reseau.
///
/// Enregistre la requete envoyee, rejoue un corps de reponse decoupe en
/// morceaux reseau arbitraires, et signale quand la requete est abandonnee
/// (annulation Dio ou abandon de la lecture du corps).
class FakeHttpAdapter implements HttpClientAdapter {
  /// Repond [statusCode] avec [body] decoupe en [chunks] (octets UTF-8).
  /// Si [keepOpen], le corps ne se termine jamais (flux en cours).
  FakeHttpAdapter.respond(
    this.statusCode,
    List<List<int>> chunks, {
    this.contentType = 'text/event-stream',
    this.keepOpen = false,
  }) : _chunks = chunks,
       _failure = null;

  /// Echoue comme le vrai `IOHttpClientAdapter` de Dio quand l'hote ne
  /// repond pas : `DioException.connectionError` sur une `SocketException`.
  FakeHttpAdapter.unreachable()
    : statusCode = 0,
      contentType = '',
      keepOpen = false,
      _chunks = const <List<int>>[],
      _failure = true;

  final int statusCode;
  final String contentType;
  final bool keepOpen;
  final List<List<int>> _chunks;
  final bool? _failure;

  /// Derniere requete recue.
  RequestOptions? request;

  /// Corps JSON de la derniere requete.
  Map<String, dynamic>? body;

  final Completer<void> _aborted = Completer<void>();

  /// Se termine quand la requete est abandonnee.
  Future<void> get aborted => _aborted.future;

  void _abort() {
    if (!_aborted.isCompleted) _aborted.complete();
  }

  /// Valeur d'un en-tete de la requete, sans tenir compte de la casse.
  String? header(String name) {
    for (final MapEntry<String, dynamic> e in request!.headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return '${e.value}';
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (requestStream != null) {
      final List<int> bytes = await requestStream
          .expand((Uint8List c) => c)
          .toList();
      body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } else if (options.data is Map) {
      body = Map<String, dynamic>.from(options.data as Map<dynamic, dynamic>);
    } else if (options.data is String) {
      body = jsonDecode(options.data as String) as Map<String, dynamic>;
    }
    unawaited(cancelFuture?.whenComplete(_abort));

    if (_failure ?? false) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
        error: const SocketException('Connection refused'),
      );
    }

    final StreamController<Uint8List> controller = StreamController<Uint8List>(
      onCancel: _abort,
    );
    () async {
      for (final List<int> chunk in _chunks) {
        // Un tour de boucle par morceau, comme des paquets reseau successifs.
        await Future<void>.delayed(Duration.zero);
        if (controller.isClosed || _aborted.isCompleted) return;
        controller.add(Uint8List.fromList(chunk));
      }
      if (!keepOpen) await controller.close();
    }();

    return ResponseBody(
      controller.stream,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Le corps en un seul morceau.
List<List<int>> whole(String body) => <List<int>>[utf8.encode(body)];

/// Le corps octet par octet : coupe les lignes, les evenements et les
/// caracteres UTF-8 multi-octets ("é" = 2 octets).
List<List<int>> byteByByte(String body) => <List<int>>[
  for (final int b in utf8.encode(body)) <int>[b],
];

/// Le corps en morceaux de [size] octets.
List<List<int>> inChunksOf(int size, String body) {
  final List<int> bytes = utf8.encode(body);
  return <List<int>>[
    for (int i = 0; i < bytes.length; i += size)
      bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
  ];
}
