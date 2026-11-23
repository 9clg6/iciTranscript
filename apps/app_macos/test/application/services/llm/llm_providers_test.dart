import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/gemini_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Fournisseurs LLM en streaming (Anthropic, OpenAI, Gemini, Ollama) derriere
/// une seule interface : une requete de chat -> un flux de morceaux de texte.
/// Le transport HTTP est injecte (Dio) : aucun test ne touche le reseau.

const String _key = 'sk-test-SECRET-0123456789';

const LlmChatRequest _request = LlmChatRequest(
  systemPrompt: 'Réponds en une phrase, en français.',
  messages: <LlmMessage>[
    LlmMessage(role: LlmRole.user, content: 'Bonjour.'),
    LlmMessage(role: LlmRole.assistant, content: 'Bonjour, je vous écoute.'),
    LlmMessage(role: LlmRole.user, content: 'Quel est le budget marketing ?'),
  ],
  model: 'model-under-test',
  maxTokens: 300,
);

const LlmChatRequest _requestWithoutModel = LlmChatRequest(
  systemPrompt: 'Réponds en français.',
  messages: <LlmMessage>[
    LlmMessage(role: LlmRole.user, content: 'Quel est le budget ?'),
  ],
  maxTokens: 300,
);

const List<String> _expectedDeltas = <String>['Le budget', ' est validé', '.'];

// Fixture d'apres l'exemple "Basic streaming request" (reponse SSE) :
// https://platform.claude.com/docs/en/build-with-claude/streaming
// (consulte le 2026-11-22). Seuls les textes des deltas sont changes.
const String _anthropicStream =
    'event: message_start\n'
    'data: {"type": "message_start", "message": {"id": "msg_1nZdL29xx5MUA1yADyHTEsnR8uuvGzszyY", "type": "message", "role": "assistant", "content": [], "model": "claude-haiku-5-5", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}\n'
    '\n'
    'event: content_block_start\n'
    'data: {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}\n'
    '\n'
    'event: ping\n'
    'data: {"type": "ping"}\n'
    '\n'
    'event: content_block_delta\n'
    'data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Le budget"}}\n'
    '\n'
    'event: content_block_delta\n'
    'data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": " est validé"}}\n'
    '\n'
    'event: content_block_delta\n'
    'data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "."}}\n'
    '\n'
    'event: content_block_stop\n'
    'data: {"type": "content_block_stop", "index": 0}\n'
    '\n'
    'event: message_delta\n'
    'data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null}, "usage": {"output_tokens": 15}}\n'
    '\n'
    'event: message_stop\n'
    'data: {"type": "message_stop"}\n'
    '\n';

// Fixture reassemblee d'apres les fragments cites des exemples de
// chat.completion.chunk (premier morceau avec le seul role, deltas de contenu,
// morceau finish_reason, champ obfuscation, puis data: [DONE]) :
// https://developers.openai.com/api/reference/resources/chat
// (consulte le 2026-11-22).
const String _openAiStream =
    'data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-6-luna","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}],"obfuscation":"r4N7vQ2m"}\n'
    '\n'
    'data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-6-luna","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"content":"Le budget"},"logprobs":null,"finish_reason":null}],"obfuscation":"r4N7vQ2m"}\n'
    '\n'
    'data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-6-luna","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"content":" est validé"},"logprobs":null,"finish_reason":null}],"obfuscation":"r4N7vQ2m"}\n'
    '\n'
    'data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-6-luna","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{"content":"."},"logprobs":null,"finish_reason":null}],"obfuscation":"r4N7vQ2m"}\n'
    '\n'
    'data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-6-luna","system_fingerprint":"fp_44709d6fcb","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"stop"}],"obfuscation":"r4N7vQ2m"}\n'
    '\n'
    'data: [DONE]\n'
    '\n';

// Fixture CONSTRUITE d'apres le schema de reference (la doc ne montre pas
// d'exemple de flux brut) : avec alt=sse, chaque evenement data: est un
// GenerateContentResponse (candidates[].content.parts[].text, role "model",
// finishReason vide jusqu'a la fin, usageMetadata).
// https://ai.google.dev/api/generate-content (models.streamGenerateContent,
// GenerateContentResponse) et
// https://ai.google.dev/gemini-api/docs/generate-content/text-generation
// ("Streaming mode: The response body contains a stream of
// GenerateContentResponse instances"), consultes le 2026-11-22.
const String _geminiStream =
    'data: {"candidates": [{"content": {"parts": [{"text": "Le budget"}],"role": "model"}}],"usageMetadata": {"promptTokenCount": 12,"candidatesTokenCount": 2,"totalTokenCount": 14}}\n'
    '\n'
    'data: {"candidates": [{"content": {"parts": [{"text": " est validé"}],"role": "model"}}],"usageMetadata": {"promptTokenCount": 12,"candidatesTokenCount": 5,"totalTokenCount": 17}}\n'
    '\n'
    'data: {"candidates": [{"content": {"parts": [{"text": "."}],"role": "model"},"finishReason": "STOP"}],"usageMetadata": {"promptTokenCount": 12,"candidatesTokenCount": 6,"totalTokenCount": 18}}\n'
    '\n';

// Fixture CONSTRUITE d'apres le schema ChatStreamEvent (application/x-ndjson :
// model, created_at, message {role, content}, done ; done vaut true sur le
// dernier evenement, dont le contenu est vide) :
// https://docs.ollama.com/api/chat et
// https://github.com/ollama/ollama/blob/main/docs/api.md ("Chat request
// (streaming)"), consultes le 2026-11-22.
const String _ollamaStream =
    '{"model":"mistral","created_at":"2026-11-22T10:00:00.000000Z","message":{"role":"assistant","content":"Le budget"},"done":false}\n'
    '{"model":"mistral","created_at":"2026-11-22T10:00:00.100000Z","message":{"role":"assistant","content":" est validé"},"done":false}\n'
    '{"model":"mistral","created_at":"2026-11-22T10:00:00.200000Z","message":{"role":"assistant","content":"."},"done":false}\n'
    '{"model":"mistral","created_at":"2026-11-22T10:00:00.300000Z","message":{"role":"assistant","content":""},"done":true}\n';

/// Un fournisseur sous test, construit sur un transport factice.
class _Case {
  const _Case(
    this.name,
    this.build,
    this.stream,
    this.contentType,
    this.defaultModel,
  );

  final String name;
  final LlmProvider Function(Dio dio) build;
  final String stream;
  final String contentType;
  final String defaultModel;
}

final List<_Case> _cases = <_Case>[
  _Case(
    'Anthropic',
    (Dio dio) => AnthropicLlmProvider(dio: dio, apiKey: _key),
    _anthropicStream,
    'text/event-stream',
    'claude-haiku-5-5',
  ),
  _Case(
    'OpenAI',
    (Dio dio) => OpenAiLlmProvider(dio: dio, apiKey: _key),
    _openAiStream,
    'text/event-stream',
    'gpt-6-luna',
  ),
  _Case(
    'Gemini',
    (Dio dio) => GeminiLlmProvider(dio: dio, apiKey: _key),
    _geminiStream,
    'text/event-stream',
    'gemini-3.5-flash-lite',
  ),
  _Case(
    'Ollama',
    (Dio dio) => OllamaLlmProvider(dio: dio),
    _ollamaStream,
    'application/x-ndjson',
    'mistral',
  ),
];

Dio _dioWith(FakeHttpAdapter adapter) => Dio()..httpClientAdapter = adapter;

Future<List<String>> _collect(
  LlmProvider provider, [
  LlmChatRequest request = _request,
]) => provider.streamChat(request).toList();

/// Execute [body] en capturant tout ce qui passe par `print` (dont le
/// LogInterceptor de Dio par defaut).
Future<T> _capturingPrints<T>(List<String> printed, Future<T> Function() body) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        printed.add(line);
      },
    ),
  );
}

List<String> _roles(Object? messages) => <String>[
  for (final dynamic m in messages! as List<dynamic>)
    (m as Map<String, dynamic>)['role'] as String,
];

void main() {
  for (final _Case c in _cases) {
    group('${c.name} : flux de texte', () {
      test(
        'transforme le flux enregistré en morceaux de texte, dans l’ordre',
        () async {
          final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
            200,
            whole(c.stream),
            contentType: c.contentType,
          );

          expect(await _collect(c.build(_dioWith(adapter))), _expectedDeltas);
        },
      );

      test('recolle les morceaux coupés au milieu d’une ligne ou d’un '
          'caractère accentué', () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
          200,
          byteByByte(c.stream),
          contentType: c.contentType,
        );

        expect(await _collect(c.build(_dioWith(adapter))), _expectedDeltas);
      });

      test('recolle des paquets de taille arbitraire', () async {
        for (final int size in <int>[7, 64, 113]) {
          final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
            200,
            inChunksOf(size, c.stream),
            contentType: c.contentType,
          );

          expect(
            await _collect(c.build(_dioWith(adapter))),
            _expectedDeltas,
            reason: 'paquets de $size octets',
          );
        }
      });

      test('donne le premier morceau avant la fin de la réponse', () async {
        // Tout jusqu'au premier evenement de texte inclus (ligne vide de fin
        // d'evenement SSE, ou fin de ligne NDJSON) ; le corps reste ouvert.
        final int lineEnd = c.stream.indexOf(
          '\n',
          c.stream.indexOf('Le budget'),
        );
        final bool ndjson = c.contentType == 'application/x-ndjson';
        final String head = c.stream.substring(0, lineEnd + (ndjson ? 1 : 2));
        final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
          200,
          whole(head),
          contentType: c.contentType,
          keepOpen: true,
        );

        final String first = await c
            .build(_dioWith(adapter))
            .streamChat(_request)
            .first
            .timeout(const Duration(seconds: 2));

        expect(first, 'Le budget');
      });

      test('annuler l’abonnement abandonne la requête', () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
          200,
          whole(c.stream.substring(0, c.stream.indexOf(' est validé'))),
          contentType: c.contentType,
          keepOpen: true,
        );
        final List<String> received = <String>[];
        final StreamSubscription<String> sub = c
            .build(_dioWith(adapter))
            .streamChat(_request)
            .listen(received.add, onError: (_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await sub.cancel();

        await expectLater(
          adapter.aborted.timeout(const Duration(seconds: 2)),
          completes,
        );
      });

      test('sans modèle demandé, utilise ${c.defaultModel}', () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
          200,
          whole(c.stream),
          contentType: c.contentType,
        );

        await _collect(c.build(_dioWith(adapter)), _requestWithoutModel);

        final String sent = c.name == 'Gemini'
            ? adapter.request!.uri.path
            : adapter.body!['model'] as String;
        expect(sent, contains(c.defaultModel));
      });
    });
  }

  group('requête envoyée', () {
    Future<FakeHttpAdapter> send(_Case c) async {
      final FakeHttpAdapter adapter = FakeHttpAdapter.respond(
        200,
        whole(c.stream),
        contentType: c.contentType,
      );
      await _collect(c.build(_dioWith(adapter)));
      return adapter;
    }

    test(
      'Anthropic : POST /v1/messages, x-api-key et anthropic-version',
      () async {
        final FakeHttpAdapter a = await send(_cases[0]);

        expect(a.request!.method, 'POST');
        expect(
          a.request!.uri.toString(),
          'https://api.anthropic.com/v1/messages',
        );
        expect(a.header('x-api-key'), _key);
        expect(
          a.header('anthropic-version'),
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        expect(a.body!['model'], 'model-under-test');
        expect(a.body!['max_tokens'], 300);
        expect(a.body!['stream'], isTrue);
        expect(
          jsonEncode(a.body!['system']),
          contains('Réponds en une phrase'),
        );
        expect(_roles(a.body!['messages']), <String>[
          'user',
          'assistant',
          'user',
        ]);
        expect(
          jsonEncode(a.body!['messages']),
          contains('Quel est le budget marketing ?'),
        );
      },
    );

    test('OpenAI : POST /v1/chat/completions, Bearer', () async {
      final FakeHttpAdapter a = await send(_cases[1]);

      expect(a.request!.method, 'POST');
      expect(
        a.request!.uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(a.header('authorization'), 'Bearer $_key');
      expect(a.body!['model'], 'model-under-test');
      expect(a.body!['max_completion_tokens'], 300);
      expect(a.body!['stream'], isTrue);
      final List<String> roles = _roles(a.body!['messages']);
      expect(roles.first, anyOf('system', 'developer'));
      expect(roles.sublist(1), <String>['user', 'assistant', 'user']);
      expect(
        jsonEncode((a.body!['messages'] as List<dynamic>).first),
        contains('Réponds en une phrase'),
      );
    });

    test('Gemini : POST models/{model}:streamGenerateContent?alt=sse, '
        'x-goog-api-key, clé absente de l’URL', () async {
      final FakeHttpAdapter a = await send(_cases[2]);

      final Uri uri = a.request!.uri;
      expect(a.request!.method, 'POST');
      expect(uri.host, 'generativelanguage.googleapis.com');
      expect(uri.path, '/v1beta/models/model-under-test:streamGenerateContent');
      expect(uri.queryParameters['alt'], 'sse');
      expect(uri.toString(), isNot(contains(_key)));
      expect(a.header('x-goog-api-key'), _key);
      expect(_roles(a.body!['contents']), <String>['user', 'model', 'user']);
      expect(
        jsonEncode(a.body!['systemInstruction']),
        contains('Réponds en une phrase'),
      );
      expect(
        (a.body!['generationConfig']
            as Map<String, dynamic>)['maxOutputTokens'],
        300,
      );
    });

    test('Ollama : POST localhost:11434/api/chat, en streaming', () async {
      final FakeHttpAdapter a = await send(_cases[3]);

      expect(a.request!.method, 'POST');
      expect(a.request!.uri.toString(), 'http://localhost:11434/api/chat');
      expect(a.body!['model'], 'model-under-test');
      expect(a.body!['stream'], isNot(false));
      expect(_roles(a.body!['messages']), <String>[
        'system',
        'user',
        'assistant',
        'user',
      ]);
      expect(
        jsonEncode((a.body!['messages'] as List<dynamic>).first),
        contains('Réponds en une phrase'),
      );
      expect((a.body!['options'] as Map<String, dynamic>)['num_predict'], 300);
    });
  });

  group('erreurs typées, sans fuite de la clé', () {
    // Certaines API renvoient la cle dans le message d'erreur ("Incorrect API
    // key provided: sk-...") : le corps factice la contient pour verifier
    // qu'elle ne remonte ni dans l'erreur ni dans les journaux.
    final String errorBody = jsonEncode(<String, Object>{
      'error': <String, String>{
        'message': 'Incorrect API key provided: $_key',
        'type': 'invalid_request_error',
      },
    });

    Future<Object> errorOf(
      _Case c,
      FakeHttpAdapter adapter,
      List<String> printed,
    ) async {
      Object? error;
      await _capturingPrints(printed, () async {
        try {
          await _collect(c.build(_dioWith(adapter)));
        } on Object catch (e) {
          error = e;
        }
      });
      expect(error, isNotNull, reason: 'le flux devait échouer');
      return error!;
    }

    for (final _Case c in _cases.take(3)) {
      test('${c.name} : 401 -> clé invalide', () async {
        final List<String> printed = <String>[];
        final Object error = await errorOf(
          c,
          FakeHttpAdapter.respond(
            401,
            whole(errorBody),
            contentType: 'application/json',
          ),
          printed,
        );

        expect(error, isA<LlmInvalidKeyException>());
        expect(error.toString(), isNot(contains(_key)));
        expect(printed.join('\n'), isNot(contains(_key)));
      });

      test('${c.name} : 429 -> limite de débit', () async {
        final List<String> printed = <String>[];
        final Object error = await errorOf(
          c,
          FakeHttpAdapter.respond(
            429,
            whole(errorBody),
            contentType: 'application/json',
          ),
          printed,
        );

        expect(error, isA<LlmRateLimitedException>());
        expect(error.toString(), isNot(contains(_key)));
        expect(printed.join('\n'), isNot(contains(_key)));
      });

      test('${c.name} : réseau coupé -> injoignable', () async {
        final List<String> printed = <String>[];
        final Object error = await errorOf(
          c,
          FakeHttpAdapter.unreachable(),
          printed,
        );

        expect(error, isA<LlmUnreachableException>());
        expect(error.toString(), isNot(contains(_key)));
        expect(printed.join('\n'), isNot(contains(_key)));
      });
    }

    // Corps d'erreur generateContent d'apres l'exemple "API key not valid" :
    // https://ai.google.dev/gemini-api/docs/generate-content/api-errors
    // (consulte le 2026-11-22). Gemini signale une cle invalide en 400.
    String geminiError(String status, {String? reason}) =>
        jsonEncode(<String, Object>{
          'error': <String, Object>{
            'code': 400,
            'message': reason == null
                ? 'Invalid JSON payload received.'
                : 'API key not valid. Please pass a valid API key.',
            'status': status,
            'details': <Object>[
              if (reason != null)
                <String, Object>{
                  '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                  'reason': reason,
                  'domain': 'googleapis.com',
                  'metadata': <String, String>{
                    'service': 'generativelanguage.googleapis.com',
                  },
                },
            ],
          },
        });

    test(
      'Gemini : 400 INVALID_ARGUMENT / API_KEY_INVALID -> clé invalide',
      () async {
        final List<String> printed = <String>[];
        final Object error = await errorOf(
          _cases[2],
          FakeHttpAdapter.respond(
            400,
            whole(geminiError('INVALID_ARGUMENT', reason: 'API_KEY_INVALID')),
            contentType: 'application/json',
          ),
          printed,
        );

        expect(error, isA<LlmInvalidKeyException>());
        expect(error.toString(), isNot(contains(_key)));
        expect(printed.join('\n'), isNot(contains(_key)));
      },
    );

    test('Gemini : 403 -> clé invalide', () async {
      final Object error = await errorOf(
        _cases[2],
        FakeHttpAdapter.respond(
          403,
          whole(
            jsonEncode(<String, Object>{
              'error': <String, Object>{
                'code': 403,
                'message':
                    'Your API key doesn\'t have the required permissions.',
                'status': 'PERMISSION_DENIED',
              },
            }),
          ),
          contentType: 'application/json',
        ),
        <String>[],
      );

      expect(error, isA<LlmInvalidKeyException>());
    });

    test('Gemini : 400 sans API_KEY_INVALID -> erreur de requête, pas '
        '« clé invalide »', () async {
      final Object error = await errorOf(
        _cases[2],
        FakeHttpAdapter.respond(
          400,
          whole(geminiError('INVALID_ARGUMENT')),
          contentType: 'application/json',
        ),
        <String>[],
      );

      expect(error, isA<LlmException>());
      expect(error, isNot(isA<LlmInvalidKeyException>()));
      expect(error.toString(), isNot(contains(_key)));
    });

    test('Ollama : serveur local arrêté -> injoignable', () async {
      final Object error = await errorOf(
        _cases[3],
        FakeHttpAdapter.unreachable(),
        <String>[],
      );

      expect(error, isA<LlmUnreachableException>());
    });
  });
}
