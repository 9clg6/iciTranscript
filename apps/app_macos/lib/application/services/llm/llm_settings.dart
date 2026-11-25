import 'package:ici_transcript/application/services/llm/mistral_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/gemini_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';

/// Choix LLM de l'utilisateur rangés dans prefs.json (jamais les clés : elles
/// vont au trousseau).
class LlmSettings {
  /// Crée des [LlmSettings].
  const LlmSettings({
    this.cloudAllowed = false,
    this.preferred,
    this.models = const <LlmProviderId, String>{},
  });

  /// Lit les choix dans [prefs] ; valeur absente ou d'un type inattendu =
  /// défaut.
  factory LlmSettings.fromPrefs(Map<String, Object?> prefs) {
    final Map<String, Object?> models =
        prefValue<Map<String, dynamic>>(prefs, modelsKey) ??
        <String, Object?>{};
    return LlmSettings(
      cloudAllowed: prefValue<bool>(prefs, cloudAllowedKey) ?? false,
      preferred: LlmProviderId.values.asNameMap()[prefs[providerKey]],
      models: <LlmProviderId, String>{
        for (final LlmProviderId id in LlmProviderId.values)
          if (models[id.name] case final String m when m.trim().isNotEmpty)
            id: m,
      },
    );
  }

  /// Clé du fournisseur choisi (`LlmProviderId.name`).
  static const String providerKey = 'llm_provider';

  /// Clé de l'autorisation d'envoi à un service en ligne (bool).
  static const String cloudAllowedKey = 'llm_cloud_allowed';

  /// Clé des modèles choisis, par `LlmProviderId.name`.
  static const String modelsKey = 'llm_models';

  /// Envoi à un service en ligne autorisé (coupé par défaut).
  final bool cloudAllowed;

  /// Fournisseur choisi ; null = repli automatique.
  final LlmProviderId? preferred;

  /// Modèles choisis ; absent = [defaultModel].
  final Map<LlmProviderId, String> models;

  /// Modèle utilisé pour [id].
  String modelFor(LlmProviderId id) => models[id] ?? defaultModel(id);

  /// Modèle rapide par défaut de [id].
  static String defaultModel(LlmProviderId id) => switch (id) {
    LlmProviderId.anthropic => AnthropicLlmProvider.defaultModel,
    LlmProviderId.openai => OpenAiLlmProvider.defaultModel,
    LlmProviderId.gemini => GeminiLlmProvider.defaultModel,
    LlmProviderId.mistral => MistralLlmProvider.defaultModel,
    LlmProviderId.ollama => OllamaLlmProvider.defaultModel,
  };
}
