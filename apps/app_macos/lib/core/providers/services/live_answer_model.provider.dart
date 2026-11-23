import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/core/providers/services/ready_llm.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_answer_model.provider.g.dart';

/// Modèle qui répond aux questions en direct ; null = aucun modèle prêt
/// (envoi coupé et modèle local absent) : rien n'est envoyé. Relu à chaque
/// question.
@riverpod
Future<LiveAnswerModel?> liveAnswerModel(Ref ref) =>
    resolveLiveAnswerModel(ref);

/// Règle de [liveAnswerModel], lisible depuis un provider gardé en vie.
///
/// Rien ne démarre ici : le démon local ne démarre qu'à la première
/// génération (une question détectée en mode local n'est que listée).
Future<LiveAnswerModel?> resolveLiveAnswerModel(Ref ref) async {
  final ReadyLlm? ready = await readyLlm(ref, start: false);
  if (ready == null) return null;
  final bool local = ready.id == LlmProviderId.ollama;
  return LiveAnswerModel(
    provider: local
        ? _StartsLocalServer(ref.read(ollamaServiceProvider), ready)
        : ready.llm,
    modelId: ready.model,
    isLocal: local,
  );
}

/// Démarre le démon local (déjà installé : rien n'est téléchargé) avant la
/// première requête.
final class _StartsLocalServer implements LlmProvider {
  _StartsLocalServer(this._ollama, this._ready);

  final OllamaService _ollama;
  final ReadyLlm _ready;

  @override
  Stream<String> streamChat(LlmChatRequest request) async* {
    try {
      await (_ollama..model = _ready.model).ensureReady().timeout(
        kLlmLocalStartTimeout,
      );
    } on Object {
      throw const LlmUnreachableException('Ollama');
    }
    yield* _ready.llm.streamChat(request);
  }
}
