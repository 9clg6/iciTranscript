import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';

part 'session_detail.state.freezed.dart';

/// Etat de l'ecran de detail d'une session.
@Freezed(copyWith: true)
abstract class SessionDetailState with _$SessionDetailState {
  /// Cree une instance de [SessionDetailState].
  const factory SessionDetailState({
    /// La session affichee.
    SessionEntity? session,

    /// Les segments de transcription de la session.
    required List<TranscriptSegmentEntity> segments,

    /// Indique si le titre est en cours d'edition.
    @Default(false) bool isEditing,

    /// Resume IA de la session, null si absent.
    String? summary,

    /// Retour du coach d'anglais, null si absent.
    EnglishFeedbackEntity? feedback,

    /// Indique si la generation du resume est en cours.
    @Default(false) bool isSummaryLoading,

    /// Indique si l'analyse du coach d'anglais est en cours.
    @Default(false) bool isFeedbackLoading,

    /// Tours de parole diarizes du meeting (Interlocuteur N).
    @Default(<SpeakerTurn>[]) List<SpeakerTurn> speakers,
  }) = _SessionDetailState;

  /// Etat initial par defaut.
  factory SessionDetailState.initial() =>
      const SessionDetailState(segments: <TranscriptSegmentEntity>[]);
}
