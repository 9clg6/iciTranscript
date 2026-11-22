import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Classe une reponse HTTP en erreur, d'apres son statut et son corps.
typedef LlmErrorClassifier =
    LlmException Function(String provider, int status, String body);

/// Délai maximal avant les en-têtes de la réponse.
const Duration kLlmConnectTimeout = Duration(seconds: 15);

/// Délai maximal avant les en-têtes pour le modèle local : Ollama n'envoie
/// ses en-têtes qu'avec le premier morceau, donc après le chargement du
/// modèle en mémoire et l'évaluation du prompt (server/routes.go,
/// ChatHandler : scheduleRunner puis streamResponse). Un premier appel à
/// froid dépasse souvent [kLlmConnectTimeout].
const Duration kLlmLocalHeaderTimeout = Duration(minutes: 3);

/// Délai maximal sans aucune donnée reçue, une fois la réponse commencée.
/// Large : un modèle qui réfléchit peut se taire avant son premier mot.
const Duration kLlmIdleTimeout = Duration(seconds: 45);

/// POST JSON en streaming : emet les lignes du corps de la reponse.
///
/// Un [CancelToken] ferme la connexion quand l'abonnement est annule
/// (annuler seulement le flux ne la ferme pas avec Dio 5.9). Les erreurs
/// HTTP et reseau deviennent des [LlmException], sans cle ni corps.
///
/// Délais appliqués ici, quel que soit le transport : [headerTimeout]
/// ([kLlmConnectTimeout] par défaut) jusqu'aux en-têtes, puis [kLlmIdleTimeout] entre deux morceaux reçus.
/// Dépassé : connexion fermée et [LlmUnreachableException].
Stream<String> postLines(
  Dio dio, {
  required String provider,
  required String url,
  required Map<String, Object?> body,
  Map<String, String> headers = const <String, String>{},
  LlmErrorClassifier classify = classifyHttpError,
  Duration headerTimeout = kLlmConnectTimeout,
}) {
  final CancelToken cancelToken = CancelToken();
  StreamSubscription<String>? subscription;
  Timer? watchdog;
  late final StreamController<String> controller;

  void stop() {
    watchdog?.cancel();
    cancelToken.cancel();
    unawaited(subscription?.cancel());
  }

  // Une seule fin : le délai, l'annulation Dio qui suit et l'erreur du flux
  // peuvent arriver l'un après l'autre.
  void fail(Object error) {
    if (controller.isClosed) return;
    stop();
    controller
      ..addError(error)
      ..close();
  }

  void finish() {
    watchdog?.cancel();
    if (!controller.isClosed) unawaited(controller.close());
  }

  void arm(Duration delay) {
    watchdog?.cancel();
    watchdog = Timer(delay, () => fail(LlmUnreachableException(provider)));
  }

  Future<void> start() async {
    arm(headerTimeout);
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

    arm(kLlmIdleTimeout);
    final Stream<String> lines = response.data!.stream
        .map((List<int> chunk) {
          arm(kLlmIdleTimeout);
          return chunk;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final int status = response.statusCode ?? 0;
    final List<String> errorBody = <String>[];
    subscription = lines.listen(
      status == 200 ? controller.add : errorBody.add,
      onError: (Object e) => fail(
        e is DioException
            ? _fromDio(provider, e)
            : LlmUnreachableException(provider),
      ),
      onDone: status == 200
          ? finish
          : () => fail(classify(provider, status, errorBody.join('\n'))),
    );
  }

  controller = StreamController<String>(
    onListen: () => unawaited(start()),
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    // Ne pas attendre la fin du flux : il peut rester ouvert indefiniment.
    onCancel: stop,
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
