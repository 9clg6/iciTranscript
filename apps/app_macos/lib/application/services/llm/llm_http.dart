import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Classe une reponse HTTP en erreur, d'apres son statut et son corps.
typedef LlmErrorClassifier =
    LlmException Function(String provider, int status, String body);

/// POST JSON en streaming : emet les lignes du corps de la reponse.
///
/// Un [CancelToken] ferme la connexion quand l'abonnement est annule
/// (annuler seulement le flux ne la ferme pas avec Dio 5.9). Les erreurs
/// HTTP et reseau deviennent des [LlmException], sans cle ni corps.
Stream<String> postLines(
  Dio dio, {
  required String provider,
  required String url,
  required Map<String, Object?> body,
  Map<String, String> headers = const <String, String>{},
  LlmErrorClassifier classify = classifyHttpError,
}) {
  final CancelToken cancelToken = CancelToken();
  StreamSubscription<String>? subscription;
  late final StreamController<String> controller;

  void fail(Object error) {
    controller
      ..addError(error)
      ..close();
  }

  Future<void> start() async {
    final Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        url,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      return fail(_fromDio(provider, e));
    }
    if (cancelToken.isCancelled) return;

    final Stream<String> lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final int status = response.statusCode ?? 0;
    if (status != 200) {
      return fail(classify(provider, status, await lines.join('\n')));
    }
    subscription = lines.listen(
      controller.add,
      onError: (Object e) => fail(
        e is DioException
            ? _fromDio(provider, e)
            : LlmUnreachableException(provider),
      ),
      onDone: controller.close,
    );
  }

  controller = StreamController<String>(
    onListen: () => unawaited(start()),
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    // Ne pas attendre la fin du flux : il peut rester ouvert indefiniment.
    onCancel: () {
      cancelToken.cancel();
      unawaited(subscription?.cancel());
    },
  );
  return controller.stream;
}

/// Classement par defaut : 401 cle invalide, 429 limite de debit.
LlmException classifyHttpError(String provider, int status, String body) {
  return switch (status) {
    401 => LlmInvalidKeyException(provider),
    429 => LlmRateLimitedException(provider),
    _ => LlmException('$provider : erreur HTTP $status'),
  };
}

LlmException _fromDio(String provider, DioException e) {
  return switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => LlmUnreachableException(provider),
    _ => LlmException('$provider : échec de la requête (${e.type.name})'),
  };
}

/// Charges utiles `data:` d'un flux Server-Sent Events, un evenement par
/// valeur (lignes `data:` multiples jointes par un saut de ligne).
///
/// Pas de generateur `async*` ici ni dans les fournisseurs : bloque dans un
/// `await for`, il ne voit l'annulation qu'au prochain evenement, donc jamais
/// si le flux reste ouvert sans rien envoyer.
Stream<String> sseData(Stream<String> lines) {
  final List<String> data = <String>[];
  return lines.transform(
    StreamTransformer<String, String>.fromHandlers(
      handleData: (String line, EventSink<String> sink) {
        if (line.isEmpty) {
          if (data.isNotEmpty) sink.add(data.join('\n'));
          data.clear();
        } else if (line.startsWith('data:')) {
          final String value = line.substring(5);
          data.add(value.startsWith(' ') ? value.substring(1) : value);
        }
      },
      handleDone: (EventSink<String> sink) {
        if (data.isNotEmpty) sink.add(data.join('\n'));
        sink.close();
      },
    ),
  );
}
