import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/core/providers/services/document_library.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answer_model.provider.dart';
import 'package:ici_transcript/core/providers/services/question_store.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'live_answers.service.provider.g.dart';

/// Questions et réponses en direct ; démarré et arrêté avec chaque
/// enregistrement par le view model du direct.
@Riverpod(keepAlive: true)
LiveAnswersService liveAnswersService(Ref ref) {
  final LiveAnswersService service = LiveAnswersService(
    resolveModel: () => resolveLiveAnswerModel(ref),
    searchDocuments: ref.watch(documentLibraryProvider).search,
    store: ref.watch(questionStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}
