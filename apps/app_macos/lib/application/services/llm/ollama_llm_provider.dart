import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

/// Ollama local via `/api/chat`, en streaming NDJSON. Sans cle.
class OllamaLlmProvider implements LlmProvider {
  /// Cree un [OllamaLlmProvider].
  OllamaLlmProvider({required Dio dio, String? model})
    : _dio = dio,
      _model = model ?? defaultModel;

  /// Modele par defaut (celui qu'installe `OllamaService`).
  static const String defaultModel = 'mistral';

  /// Contexte du modèle local. Borné : le défaut d'Ollama peut allouer un
  /// cache de plusieurs Go en mémoire unifiée. Assez pour une requête de
  /// 10 000 caractères (~3 500 jetons) plus une réponse longue.
  static const int contextTokens = 8192;

  final Dio _dio;

  /// Modele utilise quand la requete n'en demande pas.
  final String _model;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final Stream<String> lines = postLines(
      _dio,
      provider: 'Ollama',
      url: '${ollamaBaseUrl.resolve('/api/chat')}',
      body: <String, Object?>{
        'model': request.model ?? _model,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': request.systemPrompt},
          for (final LlmMessage m in request.messages)
            <String, String>{'role': m.role.name, 'content': m.content},
        ],
        'options': <String, Object?>{
          'num_predict': request.maxTokens,
          'num_ctx': contextTokens,
        },
      },
      headerTimeout: kLlmLocalHeaderTimeout,
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
