import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/get_session_detail.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'get_session_detail.use_case.provider.g.dart';

/// Provider pour [GetSessionDetailUseCase].
///
/// Recupere le detail d'une session avec ses segments de transcription.
@riverpod
GetSessionDetailUseCase getSessionDetailUseCase(Ref ref) {
  final SessionRepository sessionRepository = ref.watch(
    sessionRepositoryProvider,
  );
  final TranscriptRepository transcriptRepository = ref.watch(
    transcriptRepositoryProvider,
  );
  return GetSessionDetailUseCase(
    sessionRepository: sessionRepository,
    transcriptRepository: transcriptRepository,
  );
}
