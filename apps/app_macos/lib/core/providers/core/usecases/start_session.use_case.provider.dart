import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'start_session.use_case.provider.g.dart';

/// Provider pour [StartSessionUseCase].
///
/// Cree une nouvelle session de transcription active.
@riverpod
StartSessionUseCase startSessionUseCase(Ref ref) {
  final SessionRepository repository = ref.watch(sessionRepositoryProvider);
  return StartSessionUseCase(sessionRepository: repository);
}
