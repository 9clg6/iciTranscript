import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/delete_session.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'delete_session.use_case.provider.g.dart';

/// Provider pour [DeleteSessionUseCase].
///
/// Supprime une session et ses segments de transcription associes.
@riverpod
DeleteSessionUseCase deleteSessionUseCase(Ref ref) {
  final SessionRepository sessionRepository = ref.watch(
    sessionRepositoryProvider,
  );
  final TranscriptRepository transcriptRepository = ref.watch(
    transcriptRepositoryProvider,
  );
  return DeleteSessionUseCase(
    sessionRepository: sessionRepository,
    transcriptRepository: transcriptRepository,
  );
}
