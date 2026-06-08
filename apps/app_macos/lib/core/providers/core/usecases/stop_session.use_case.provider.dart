import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stop_session.use_case.provider.g.dart';

/// Provider pour [StopSessionUseCase].
///
/// Arrete une session de transcription en cours et met a jour son statut.
@riverpod
StopSessionUseCase stopSessionUseCase(Ref ref) {
  final SessionRepository repository = ref.watch(sessionRepositoryProvider);
  return StopSessionUseCase(sessionRepository: repository);
}
