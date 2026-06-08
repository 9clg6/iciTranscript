import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/usecases/update_session_title.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_session_title.use_case.provider.g.dart';

/// Provider pour [UpdateSessionTitleUseCase].
///
/// Met a jour le titre d'une session de transcription.
@riverpod
UpdateSessionTitleUseCase updateSessionTitleUseCase(Ref ref) {
  final SessionRepository repository = ref.watch(sessionRepositoryProvider);
  return UpdateSessionTitleUseCase(sessionRepository: repository);
}
