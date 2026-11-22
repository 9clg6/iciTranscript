import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/gemini_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_llm_provider.provider.g.dart';

/// Fournisseur LLM actif, construit avec sa cle du trousseau.
///
/// A invalider apres l'ecriture ou la suppression d'une cle.
@Riverpod(keepAlive: true)
Future<LlmProvider> activeLlmProvider(Ref ref) async {
  final ApiKeyStore store = ref.watch(apiKeyStoreProvider);
  // ponytail: pas encore de choix utilisateur (`preferred`) ; il arrive
  // avec la tranche reglages.
  final LlmProviderId id = await LlmProviderSelection(store).activeProvider();
  final String key = await store.read(id) ?? '';
  final Dio dio = Dio();
  ref.onDispose(dio.close);
  return switch (id) {
    LlmProviderId.anthropic => AnthropicLlmProvider(dio: dio, apiKey: key),
    LlmProviderId.openai => OpenAiLlmProvider(dio: dio, apiKey: key),
    LlmProviderId.gemini => GeminiLlmProvider(dio: dio, apiKey: key),
    LlmProviderId.ollama => OllamaLlmProvider(dio: dio),
  };
}
