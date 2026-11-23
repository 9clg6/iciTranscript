import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

import '../../../helpers/settings_fakes.dart';

/// Délais des requêtes LLM, définis en un seul endroit (besoin 5).
///
/// API supposée (llm_http.dart) : `const Duration kLlmConnectTimeout`,
/// `const Duration kLlmIdleTimeout` (aucune donnée reçue). Appliqués dans
/// `postLines`, donc à tous les fournisseurs et quel que soit le transport.
const String _key = 'sk-test-SECRET-0123456789';
const Duration _second = Duration(seconds: 1);

String _delta(String text) =>
    'event: content_block_delta\n'
    'data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "$text"}}\n'
    '\n';

/// Serveur lent mais vivant : un morceau toutes les [every], [count] fois,
/// puis fin.
class _DripAdapter implements HttpClientAdapter {
  _DripAdapter({required this.every, required this.count});

  final Duration every;
  final int count;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final StreamController<Uint8List> controller =
        StreamController<Uint8List>();
    int sent = 0;
    Timer.periodic(every, (Timer t) {
      if (controller.isClosed) return t.cancel();
      controller.add(utf8.encode(_delta('m$sent')));
      if (++sent == count) {
        t.cancel();
        unawaited(controller.close());
      }
    });
    return ResponseBody(
      controller.stream,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('les deux délais existent et sont positifs', () {
    expect(kLlmConnectTimeout, greaterThan(Duration.zero));
    expect(kLlmIdleTimeout, greaterThan(Duration.zero));
  });

  test('serveur muet : « injoignable » au plus tard un instant après le '
      'délai d\'inactivité, pas avant', () {
    fakeAsync((FakeAsync async) {
      final RecordingHttpAdapter adapter = RecordingHttpAdapter(
        reply: BodyReply(200, _delta('Le budget'), keepOpen: true),
      );
      final List<Object> errors = <Object>[];
      AnthropicLlmProvider(
        dio: Dio()..httpClientAdapter = adapter,
        apiKey: _key,
      ).streamChat(kPing).listen((_) {}, onError: errors.add);

      async.elapse(const Duration(milliseconds: 100));
      async.elapse(kLlmIdleTimeout - _second);
      expect(errors, isEmpty, reason: 'coupé avant le délai');

      async.elapse(_second * 2);
      expect(errors.single, isA<LlmUnreachableException>());
    });
  });

  test('serveur lent mais vivant : aucune erreur tant que des données '
      'arrivent, même au-delà du délai au total', () {
    fakeAsync((FakeAsync async) {
      // Un morceau toutes les 60 % du délai, 5 fois : 3 délais au total.
      final Duration every = kLlmIdleTimeout * 0.6;
      final List<String> texts = <String>[];
      final List<Object> errors = <Object>[];
      bool done = false;
      AnthropicLlmProvider(
            dio: Dio()
              ..httpClientAdapter = _DripAdapter(every: every, count: 5),
            apiKey: _key,
          )
          .streamChat(kPing)
          .listen(texts.add, onError: errors.add, onDone: () => done = true);

      async.elapse(every * 6);

      expect(errors, isEmpty);
      expect(texts, <String>['m0', 'm1', 'm2', 'm3', 'm4']);
      expect(done, isTrue);
    });
  });

  test('aucune réponse : « injoignable » au plus tard après connexion + '
      'inactivité', () {
    fakeAsync((FakeAsync async) {
      final List<Object> errors = <Object>[];
      AnthropicLlmProvider(
        dio: Dio()
          ..httpClientAdapter = RecordingHttpAdapter(reply: const HangReply()),
        apiKey: _key,
      ).streamChat(kPing).listen((_) {}, onError: errors.add);

      async.elapse(kLlmConnectTimeout + kLlmIdleTimeout + _second);

      expect(errors.single, isA<LlmUnreachableException>());
    });
  });

  test('annuler avant le délai : aucune erreur levée ensuite', () {
    fakeAsync((FakeAsync async) {
      final List<Object> errors = <Object>[];
      final StreamSubscription<String> sub = AnthropicLlmProvider(
        dio: Dio()
          ..httpClientAdapter = RecordingHttpAdapter(
            reply: BodyReply(200, _delta('Le'), keepOpen: true),
          ),
        apiKey: _key,
      ).streamChat(kPing).listen((_) {}, onError: errors.add);

      async.elapse(const Duration(milliseconds: 100));
      unawaited(sub.cancel());
      async.elapse(kLlmConnectTimeout + kLlmIdleTimeout * 2);

      expect(errors, isEmpty);
      expect(async.pendingTimers, isEmpty, reason: 'minuteur laissé actif');
    });
  });
}
