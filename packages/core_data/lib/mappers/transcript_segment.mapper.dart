import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';

import 'package:core_data/model/local/transcript_segment.local.model.dart';

/// Extensions de mapping pour [TranscriptSegmentLocalModel].
extension TranscriptSegmentLocalModelX on TranscriptSegmentLocalModel {
  /// Convertit en [TranscriptSegmentEntity].
  TranscriptSegmentEntity toEntity() => TranscriptSegmentEntity(
    id: id,
    sessionId: sessionId,
    source: AudioSource.values.byName(source),
    text: text,
    timestampMs: timestampMs,
    createdAt: DateTime.parse(createdAt),
    isPartial: isPartial,
  );
}

/// Extensions de mapping pour [TranscriptSegmentEntity] vers le modele local.
extension TranscriptSegmentEntityToLocalX on TranscriptSegmentEntity {
  /// Convertit en [TranscriptSegmentLocalModel].
  TranscriptSegmentLocalModel toLocalModel() => TranscriptSegmentLocalModel(
    id: id,
    sessionId: sessionId,
    source: source.name,
    text: text,
    timestampMs: timestampMs,
    createdAt: createdAt.toIso8601String(),
    isPartial: isPartial,
  );
}
