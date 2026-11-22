import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/llm_http.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Gemini via `streamGenerateContent` (API Google AI), en streaming SSE.
class GeminiLlmProvider implements LlmProvider {
  /// Cree un [GeminiLlmProvider].
  GeminiLlmProvider({required Dio dio, required String apiKey, String? model})
    : _dio = dio,
      _apiKey = apiKey,
      _model = model ?? defaultModel;

  /// Modele rapide par defaut.
  static const String defaultModel = 'gemini-3.5-flash-lite';

  final Dio _dio;
  final String _apiKey;

  /// Modele utilise quand la requete n'en demande pas.
  final String _model;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final String model = request.model ?? _model;
    final Stream<String> lines = postLines(
      _dio,
      provider: 'Gemini',
      // La cle passe en en-tete, jamais dans l'URL (journaux, proxys).
      url:
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:streamGenerateContent?alt=sse',
      headers: <String, String>{'x-goog-api-key': _apiKey},
      classify: _classify,
      body: <String, Object?>{
        'systemInstruction': <String, Object?>{
          'parts': <Map<String, String>>[
            <String, String>{'text': request.systemPrompt},
          ],
        },
        'contents': <Map<String, Object?>>[
          for (final LlmMessage m in request.messages)
            <String, Object?>{
              'role': m.role == LlmRole.user ? 'user' : 'model',
              'parts': <Map<String, String>>[
                <String, String>{'text': m.content},
              ],
            },
        ],
        'generationConfig': <String, Object?>{
          'maxOutputTokens': request.maxTokens,
        },
      },
    );
    return sseData(lines).expand(_texts);
  }

  static Iterable<String> _texts(String data) {
    final Map<String, dynamic> response =
        jsonDecode(data) as Map<String, dynamic>;
    if (response['error'] != null) {
      throw const LlmException('Gemini : erreur pendant la réponse');
    }
    return <String>[
      for (final dynamic candidate
          in response['candidates'] as List<dynamic>? ?? <dynamic>[])
        for (final dynamic part
            in (((candidate as Map<String, dynamic>)['content']
                        as Map<String, dynamic>?)?['parts']
                    as List<dynamic>?) ??
                <dynamic>[])
          if ((part as Map<String, dynamic>)['text'] case final String text
              when text.isNotEmpty)
            text,
    ];
  }

  /// Gemini signale une cle invalide en 400 (`API_KEY_INVALID`) ou 403.
  static LlmException _classify(String provider, int status, String body) {
    if (status == 403 || (status == 400 && body.contains('API_KEY_INVALID'))) {
      return LlmInvalidKeyException(provider);
    }
    return classifyHttpError(provider, status, body);
  }
}
