import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/gemini_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_llm_provider.provider.g.dart';

/// Fournisseur LLM actif : choix de Réglages (prefs.json) et clé du
/// trousseau, avec le repli de [LlmProviderSelection].
///
/// Lu une fois puis gardé : Réglages l'invalide après chaque changement de
/// clé, de fournisseur, de modèle ou d'autorisation d'envoi.
@Riverpod(keepAlive: true)
Future<LlmProvider> activeLlmProvider(Ref ref) async {
  final ApiKeyStore store = ref.watch(apiKeyStoreProvider);
  final LlmSettings settings = LlmSettings.fromPrefs(
    await ref.watch(prefsStoreProvider).read(),
  );
  final LlmProviderId id = await resolveActiveLlmProvider(store, settings);
  return buildLlmProvider(
    id,
    dio: ref.watch(llmDioProvider),
    apiKey: id == LlmProviderId.ollama ? '' : await store.read(id) ?? '',
    model: settings.modelFor(id),
  );
}

/// Fournisseur réellement utilisé pour [settings] (une seule règle, pour
/// l'app et pour le menu de Réglages). Trousseau illisible : modèle local.
Future<LlmProviderId> resolveActiveLlmProvider(
  ApiKeyStore store,
  LlmSettings settings,
) async {
  try {
    return await LlmProviderSelection(store).activeProvider(
      preferred: settings.preferred,
      cloudAllowed: settings.cloudAllowed,
    );
  } on Object {
    return LlmProviderId.ollama;
  }
}

/// Construit le fournisseur [id].
LlmProvider buildLlmProvider(
  LlmProviderId id, {
  required Dio dio,
  required String apiKey,
  required String model,
}) => switch (id) {
  LlmProviderId.anthropic => AnthropicLlmProvider(
    dio: dio,
    apiKey: apiKey,
    model: model,
  ),
  LlmProviderId.openai => OpenAiLlmProvider(
    dio: dio,
    apiKey: apiKey,
    model: model,
  ),
  LlmProviderId.gemini => GeminiLlmProvider(
    dio: dio,
    apiKey: apiKey,
    model: model,
  ),
  LlmProviderId.ollama => OllamaLlmProvider(dio: dio, model: model),
};
