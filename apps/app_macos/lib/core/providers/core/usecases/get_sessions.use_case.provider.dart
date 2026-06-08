import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/usecases/get_sessions.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'get_sessions.use_case.provider.g.dart';

/// Provider pour [GetSessionsUseCase].
///
/// Recupere la liste de toutes les sessions de transcription.
@riverpod
GetSessionsUseCase getSessionsUseCase(Ref ref) {
  final SessionRepository repository = ref.watch(sessionRepositoryProvider);
  return GetSessionsUseCase(sessionRepository: repository);
}
