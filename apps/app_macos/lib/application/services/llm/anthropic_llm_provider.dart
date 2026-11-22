import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Claude via l'API Messages d'Anthropic, en streaming SSE.
class AnthropicLlmProvider implements LlmProvider {
  /// Cree un [AnthropicLlmProvider].
  AnthropicLlmProvider({required Dio dio, required String apiKey})
    : _dio = dio,
      _apiKey = apiKey;

  /// Modele rapide par defaut.
  static const String defaultModel = 'claude-haiku-5-5';

  /// Version de l'API (en-tete `anthropic-version`).
  static const String apiVersion = '2026-10-21';

  final Dio _dio;
  final String _apiKey;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final Stream<String> lines = postLines(
      _dio,
      provider: 'Anthropic',
      url: 'https://api.anthropic.com/v1/messages',
      headers: <String, String>{
        'x-api-key': _apiKey,
        'anthropic-version': apiVersion,
      },
      body: <String, Object?>{
        'model': request.model ?? defaultModel,
        'max_tokens': request.maxTokens,
        'stream': true,
        'system': request.systemPrompt,
        'messages': <Map<String, String>>[
          for (final LlmMessage m in request.messages)
            <String, String>{'role': m.role.name, 'content': m.content},
        ],
      },
    );
    return sseData(lines).expand(_texts);
  }

  static Iterable<String> _texts(String data) {
    final Map<String, dynamic> event = jsonDecode(data) as Map<String, dynamic>;
    switch (event['type']) {
      case 'content_block_delta':
        final Map<String, dynamic> delta =
            event['delta'] as Map<String, dynamic>;
        if (delta['type'] == 'text_delta') {
          return <String>[delta['text'] as String];
        }
      case 'error':
        throw const LlmException('Anthropic : erreur pendant la réponse');
    }
    return const <String>[];
  }
}
