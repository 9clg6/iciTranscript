import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_segment.local.model.freezed.dart';
part 'transcript_segment.local.model.g.dart';

/// Modele de donnees local pour un segment de transcription (SQLite/Drift).
@freezed
abstract class TranscriptSegmentLocalModel with _$TranscriptSegmentLocalModel {
  /// Cree une instance de [TranscriptSegmentLocalModel].
  const factory TranscriptSegmentLocalModel({
    /// Identifiant unique du segment.
    required String id,

    /// Identifiant de la session parente.
    required String sessionId,

    /// Source audio (input ou output).
    required String source,

    /// Texte transcrit.
    required String text,

    /// Offset en millisecondes depuis le debut de la session.
    required int timestampMs,

    /// Date de creation au format ISO 8601.
    required String createdAt,

    /// Texte connu incomplet (schema v3).
    @Default(false) bool isPartial,
  }) = _TranscriptSegmentLocalModel;

  /// Cree une instance depuis un JSON.
  factory TranscriptSegmentLocalModel.fromJson(Map<String, dynamic> json) =>
      _$TranscriptSegmentLocalModelFromJson(json);
}
