import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// OpenAI via Chat Completions, en streaming SSE.
class OpenAiLlmProvider implements LlmProvider {
  /// Cree un [OpenAiLlmProvider].
  OpenAiLlmProvider({required Dio dio, required String apiKey, String? model})
    : _dio = dio,
      _apiKey = apiKey,
      _model = model ?? defaultModel;

  /// Modele rapide par defaut.
  static const String defaultModel = 'gpt-6-luna';

  final Dio _dio;
  final String _apiKey;

  /// Modele utilise quand la requete n'en demande pas.
  final String _model;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final Stream<String> lines = postLines(
      _dio,
      provider: 'OpenAI',
      url: 'https://api.openai.com/v1/chat/completions',
      headers: <String, String>{'Authorization': 'Bearer $_apiKey'},
      body: <String, Object?>{
        'model': request.model ?? _model,
        'max_completion_tokens': request.maxTokens,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'developer',
            'content': request.systemPrompt,
          },
          for (final LlmMessage m in request.messages)
            <String, String>{'role': m.role.name, 'content': m.content},
        ],
      },
    );
    return sseData(lines).expand(_texts);
  }

  static Iterable<String> _texts(String data) {
    if (data == '[DONE]') return const <String>[];
    final Map<String, dynamic> chunk = jsonDecode(data) as Map<String, dynamic>;
    if (chunk['error'] != null) {
      throw const LlmException('OpenAI : erreur pendant la réponse');
    }
    return <String>[
      for (final dynamic choice in chunk['choices'] as List<dynamic>)
        if (((choice as Map<String, dynamic>)['delta']
                as Map<String, dynamic>?)?['content']
            case final String content when content.isNotEmpty)
          content,
    ];
  }
}
