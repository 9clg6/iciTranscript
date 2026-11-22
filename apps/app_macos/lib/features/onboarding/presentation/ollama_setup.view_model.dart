import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ollama_setup.view_model.g.dart';

/// ViewModel du modèle local (moteur Ollama + modèle choisi dans Réglages,
/// Mistral par défaut).
///
/// [build] détecte seulement (aucun téléchargement) ; [install] lance
/// l'installation (~106 Mo + ~4 Go) à la demande, depuis Réglages.
@Riverpod(keepAlive: true)
class OllamaSetupViewModel extends _$OllamaSetupViewModel {
  @override
  OllamaSetupState build() {
    _detect();
    return const OllamaSetupState();
  }

  /// Le service vise le modèle local choisi dans Réglages.
  Future<OllamaService> _selected() async {
    final String model = LlmSettings.fromPrefs(
      await ref.read(prefsStoreProvider).read(),
    ).modelFor(LlmProviderId.ollama);
    final OllamaService service = ref.read(ollamaServiceProvider);
    service.model = model;
    return service;
  }

  Future<void> _detect() async {
    final OllamaService service = await _selected();
    final bool installed = await service.isInstalled(model: service.model);
    if (installed) {
      state = state.copyWith(
        stage: OllamaSetupStage.ready,
        isReady: true,
        progress: 1.0,
      );
    }
  }

  /// Installe le moteur et le modèle, avec la progression de chaque étape.
  Future<void> install() async {
    state = const OllamaSetupState(stage: OllamaSetupStage.downloadingBinary);
    try {
      await (await _selected()).ensureReady(
            onProgress: (OllamaSetupStage stage, double progress) {
              state = state.copyWith(stage: stage, progress: progress);
            },
          );
      state = state.copyWith(
        stage: OllamaSetupStage.ready,
        isReady: true,
        progress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        stage: OllamaSetupStage.error,
        error: e.toString(),
      );
    }
  }

  /// Relance l'installation après une erreur.
  void retry() => install();
}
