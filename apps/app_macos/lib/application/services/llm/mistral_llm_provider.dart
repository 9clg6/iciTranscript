import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';

/// Mistral (API compatible OpenAI). La même clé sert à la transcription en
/// ligne (trousseau, compte `mistral`).
class MistralLlmProvider implements LlmProvider {
  /// Cree un [MistralLlmProvider].
  MistralLlmProvider({required Dio dio, required String apiKey, String? model})
    : _dio = dio,
      _apiKey = apiKey,
      _model = model ?? defaultModel;

  /// Modele rapide par defaut.
  static const String defaultModel = 'mistral-small-latest';

  final Dio _dio;
  final String _apiKey;
  final String _model;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final Stream<String> lines = postLines(
      _dio,
      provider: 'Mistral',
      url: 'https://api.mistral.ai/v1/chat/completions',
      headers: <String, String>{'Authorization': 'Bearer $_apiKey'},
      body: <String, Object?>{
        'model': request.model ?? _model,
        'max_tokens': request.maxTokens,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': request.systemPrompt},
          for (final LlmMessage m in request.messages)
            <String, String>{'role': m.role.name, 'content': m.content},
        ],
      },
    );
    return sseData(lines).expand(
      (String data) => OpenAiLlmProvider.chatTexts(data, provider: 'Mistral'),
    );
  }
}
