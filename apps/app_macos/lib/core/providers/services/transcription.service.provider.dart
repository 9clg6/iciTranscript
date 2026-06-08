import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:ici_transcript/core/providers/core/usecases/save_transcript_segment.use_case.provider.dart';
import 'package:ici_transcript/core/providers/core/usecases/start_session.use_case.provider.dart';
import 'package:ici_transcript/core/providers/core/usecases/stop_session.use_case.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcription.service.provider.g.dart';

/// Provider singleton pour [TranscriptionService].
///
/// Orchestre le cycle de vie d'une session de transcription :
/// demarrage, arret, sauvegarde des segments.
/// Maintient un etat reactif via [BehaviorSubject].
@Riverpod(keepAlive: true)
TranscriptionService transcriptionService(Ref ref) {
  final StartSessionUseCase startSessionUseCase = ref.watch(
    startSessionUseCaseProvider,
  );
  final StopSessionUseCase stopSessionUseCase = ref.watch(
    stopSessionUseCaseProvider,
  );
  final SaveTranscriptSegmentUseCase saveTranscriptSegmentUseCase = ref.watch(
    saveTranscriptSegmentUseCaseProvider,
  );

  final TranscriptionService service = TranscriptionService(
    startSessionUseCase: startSessionUseCase,
    stopSessionUseCase: stopSessionUseCase,
    saveTranscriptSegmentUseCase: saveTranscriptSegmentUseCase,
  );

  ref.onDispose(service.dispose);
  return service;
}
