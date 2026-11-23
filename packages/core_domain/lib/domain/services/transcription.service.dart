import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/params/stop_session.param.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:core_foundation/interfaces/results.usecases.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:rxdart/rxdart.dart';

/// Service orchestrant le cycle de vie d'une session de transcription.
///
/// Coordonne le demarrage/arret de session, la sauvegarde des segments
/// et maintient un etat reactif via [BehaviorSubject].
final class TranscriptionService {
  /// Cree une instance de [TranscriptionService].
  TranscriptionService({
    required StartSessionUseCase startSessionUseCase,
    required StopSessionUseCase stopSessionUseCase,
    required SaveTranscriptSegmentUseCase saveTranscriptSegmentUseCase,
  }) : _startSessionUseCase = startSessionUseCase,
       _stopSessionUseCase = stopSessionUseCase,
       _saveTranscriptSegmentUseCase = saveTranscriptSegmentUseCase;

  final StartSessionUseCase _startSessionUseCase;
  final StopSessionUseCase _stopSessionUseCase;
  final SaveTranscriptSegmentUseCase _saveTranscriptSegmentUseCase;

  final Log _log = Log.named('TranscriptionService');

  /// Stream reactif de la session courante.
  final BehaviorSubject<SessionEntity?> currentSessionStream =
      BehaviorSubject<SessionEntity?>.seeded(null);

  /// Stream reactif des segments de la session courante.
  final BehaviorSubject<List<TranscriptSegmentEntity>> segmentsStream =
      BehaviorSubject<List<TranscriptSegmentEntity>>.seeded(
        <TranscriptSegmentEntity>[],
      );

  /// Stream reactif indiquant si une transcription est en cours.
  final BehaviorSubject<bool> isTranscribingStream =
      BehaviorSubject<bool>.seeded(false);

  /// Demarre une nouvelle session de transcription, liee a [link] s'il y en
  /// a un.
  Future<void> startSession({SessionCalendarLink? link}) async {
    final ResultState<SessionEntity> result = await _startSessionUseCase
        .executeLinked(link);
    result.when(
      success: (SessionEntity session) {
        currentSessionStream.add(session);
        segmentsStream.add(<TranscriptSegmentEntity>[]);
        isTranscribingStream.add(true);
        _log.info('Session demarree : ${session.id}');
      },
      failure: (Exception e) {
        _log.error('Erreur demarrage session', e);
      },
    );
  }

  /// Arrete la session de transcription en cours.
  Future<void> stopSession() async {
    final SessionEntity? currentSession = currentSessionStream.valueOrNull;
    if (currentSession == null ||
        currentSession.status != SessionStatus.active) {
      _log.warning('Aucune session active a arreter');
      return;
    }
    final ResultState<SessionEntity> result = await _stopSessionUseCase.execute(
      StopSessionParam(sessionId: currentSession.id),
    );
    result.when(
      success: (SessionEntity session) {
        currentSessionStream.add(session);
        isTranscribingStream.add(false);
        _log.info('Session arretee : ${session.id}');
      },
      failure: (Exception e) {
        _log.error('Erreur arret session', e);
      },
    );
  }

  /// Sauvegarde un segment de transcription et met a jour le stream.
  ///
  /// Un segment de meme id (provisoire) est remplace, en base et a l'ecran.
  Future<void> saveSegment(TranscriptSegmentEntity segment) async {
    final ResultState<TranscriptSegmentEntity> result =
        await _saveTranscriptSegmentUseCase.execute(segment);
    result.when(
      success: (TranscriptSegmentEntity savedSegment) {
        final List<TranscriptSegmentEntity> currentSegments =
            List<TranscriptSegmentEntity>.from(segmentsStream.value)
              ..removeWhere(
                (TranscriptSegmentEntity s) => s.id == savedSegment.id,
              );
        currentSegments.add(savedSegment);
        segmentsStream.add(currentSegments);
      },
      failure: (Exception e) {
        _log.error('Erreur sauvegarde segment', e);
      },
    );
  }

  /// Sauve en base la phrase en cours, sans la montrer : l'ecran garde son
  /// segment temporaire. La phrase finale la remplacera (meme id).
  Future<void> saveProvisional(TranscriptSegmentEntity segment) async {
    final ResultState<TranscriptSegmentEntity> result =
        await _saveTranscriptSegmentUseCase.execute(segment);
    result.when(
      success: (_) {},
      failure: (Exception e) {
        _log.error('Erreur sauvegarde segment provisoire', e);
      },
    );
  }

  /// Retire de la base un segment provisoire dont la phrase a ete ecartee.
  Future<void> discardProvisional(String segmentId) async {
    try {
      await _saveTranscriptSegmentUseCase.discard(segmentId);
    } on Exception catch (e) {
      _log.error('Erreur suppression segment provisoire', e);
    }
  }

  /// Libere les ressources du service.
  void dispose() {
    currentSessionStream.close();
    segmentsStream.close();
    isTranscribingStream.close();
  }
}
