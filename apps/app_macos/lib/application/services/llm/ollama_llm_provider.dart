import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

/// Ollama local via `/api/chat`, en streaming NDJSON. Sans cle.
class OllamaLlmProvider implements LlmProvider {
  /// Cree un [OllamaLlmProvider].
  OllamaLlmProvider({required Dio dio}) : _dio = dio;

  /// Modele par defaut (celui qu'installe `OllamaService`).
  static const String defaultModel = 'mistral';

  final Dio _dio;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final Stream<String> lines = postLines(
      _dio,
      provider: 'Ollama',
      url: '${ollamaBaseUrl.resolve('/api/chat')}',
      body: <String, Object?>{
        'model': request.model ?? defaultModel,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': request.systemPrompt},
          for (final LlmMessage m in request.messages)
            <String, String>{'role': m.role.name, 'content': m.content},
        ],
        'options': <String, Object?>{'num_predict': request.maxTokens},
      },
    );
    return lines.expand(_texts);
  }

  static Iterable<String> _texts(String line) {
    if (line.trim().isEmpty) return const <String>[];
    final Map<String, dynamic> event = jsonDecode(line) as Map<String, dynamic>;
    if (event['error'] != null) {
      throw const LlmException('Ollama : erreur pendant la réponse');
    }
    return <String>[
      if ((event['message'] as Map<String, dynamic>?)?['content']
          case final String content when content.isNotEmpty)
        content,
    ];
  }
}
