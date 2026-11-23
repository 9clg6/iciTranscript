import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart'
    show LiveAnswerModel;
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/core/providers/services/live_answer_model.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_coach.service.provider.g.dart';

/// Coach anglais en direct ; démarré et arrêté avec chaque enregistrement
/// (interrupteur activé) par le view model du direct. Même modèle que les
/// réponses en direct ; seul un fournisseur en ligne reçoit les phrases.
@Riverpod(keepAlive: true)
LiveCoachService liveCoachService(Ref ref) {
  final LiveCoachService service = LiveCoachService(
    resolveModel: () => resolveLiveAnswerModel(ref),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Ce que le coach en direct a trouvé, à chaque changement.
@riverpod
Stream<LiveCoachSnapshot> liveCoachSnapshot(Ref ref) =>
    ref.watch(liveCoachServiceProvider).snapshots;

/// Le coach en direct peut-il partir ? Seulement vers un fournisseur en
/// ligne configuré et autorisé (même règle que le service).
@riverpod
Future<bool> liveCoachAvailable(Ref ref) async {
  try {
    final LiveAnswerModel? model = await resolveLiveAnswerModel(ref);
    return model != null && !model.isLocal;
  } on Object {
    return false;
  }
}
