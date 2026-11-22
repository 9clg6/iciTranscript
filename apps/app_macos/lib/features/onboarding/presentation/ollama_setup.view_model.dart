import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ollama_setup.view_model.g.dart';

/// ViewModel du modèle local (moteur Ollama + modèle Mistral).
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

  Future<void> _detect() async {
    final bool installed = await ref.read(ollamaServiceProvider).isInstalled();
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
      await ref
          .read(ollamaServiceProvider)
          .ensureReady(
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
