import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'save_transcript_segment.use_case.provider.g.dart';

/// Provider pour [SaveTranscriptSegmentUseCase].
///
/// Sauvegarde un segment de transcription dans la base de donnees locale.
@riverpod
SaveTranscriptSegmentUseCase saveTranscriptSegmentUseCase(Ref ref) {
  final TranscriptRepository repository = ref.watch(
    transcriptRepositoryProvider,
  );
  return SaveTranscriptSegmentUseCase(transcriptRepository: repository);
}
