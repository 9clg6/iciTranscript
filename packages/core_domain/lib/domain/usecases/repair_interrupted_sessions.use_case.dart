import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_foundation/interfaces/future.usecases.dart';

/// Ferme les sessions restees `active` apres un arret brutal de l'app.
///
/// A appeler au lancement, avant toute nouvelle session : la duree est
/// celle du dernier segment sauve, les segments sont gardes.
final class RepairInterruptedSessionsUseCase extends FutureUseCase<void> {
  /// Cree une instance de [RepairInterruptedSessionsUseCase].
  RepairInterruptedSessionsUseCase({
    required SessionRepository sessionRepository,
    required TranscriptRepository transcriptRepository,
  }) : _sessionRepository = sessionRepository,
       _transcriptRepository = transcriptRepository;

  final SessionRepository _sessionRepository;
  final TranscriptRepository _transcriptRepository;

  @override
  Future<void> invoke() async {
    final List<SessionEntity> sessions = await _sessionRepository.getAll();
    for (final SessionEntity session in sessions) {
      if (session.status != SessionStatus.active) continue;
      final List<TranscriptSegmentEntity> segments = await _transcriptRepository
          .getBySessionId(session.id);
      int lastMs = 0;
      for (final TranscriptSegmentEntity segment in segments) {
        if (segment.timestampMs > lastMs) lastMs = segment.timestampMs;
      }
      final Duration duration = Duration(milliseconds: lastMs);
      await _sessionRepository.update(
        session.copyWith(
          status: SessionStatus.interrupted,
          durationSeconds: duration.inSeconds,
          updatedAt: session.createdAt.add(duration),
        ),
      );
    }
  }
}
