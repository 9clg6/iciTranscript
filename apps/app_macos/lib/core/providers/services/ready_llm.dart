import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Attente maximale du démarrage du démon local avant « injoignable ».
const Duration kLlmLocalStartTimeout = Duration(seconds: 60);

/// Fournisseur prêt à répondre, modèle qu'il utilise et son id.
typedef ReadyLlm = ({LlmProvider llm, String model, LlmProviderId id});

/// Où partira une requête IA : fournisseur en ligne s'il est configuré,
/// autorisé et choisi, sinon le modèle local s'il est installé. Null :
/// rien d'utilisable (la note invite à configurer un modèle) ; rien n'est
/// envoyé ni téléchargé.
///
/// Avec [start], démarre le serveur local installé (sans téléchargement :
/// binaire et modèle sont déjà là).
Future<ReadyLlm?> readyLlm(Ref ref, {bool start = true}) async {
  final ApiKeyStore keys = ref.read(apiKeyStoreProvider);
  final LlmSettings settings = LlmSettings.fromPrefs(
    await ref.read(prefsStoreProvider).read(),
  );
  final LlmProviderId id = await resolveActiveLlmProvider(keys, settings);
  final String model = settings.modelFor(id);
  if (id == LlmProviderId.ollama) {
    final OllamaService ollama = ref.read(ollamaServiceProvider);
    // Le modèle choisi, pas seulement mistral ; présent, ensureReady ne
    // fait que démarrer le serveur.
    if (!await ollama.isInstalled(model: model)) return null;
    if (start) {
      // Démarrage borné ; un démon qui ne démarre pas = injoignable.
      try {
        await (ollama..model = model).ensureReady().timeout(
          kLlmLocalStartTimeout,
        );
      } on Object {
        throw const LlmUnreachableException('Ollama');
      }
    }
  }
  return (
    llm: await ref.read(activeLlmProviderProvider.future),
    model: model,
    id: id,
  );
}
