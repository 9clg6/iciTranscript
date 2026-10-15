import 'package:core_domain/domain/entities/transcript_segment.entity.dart';

/// Bloc affiché : une ou plusieurs phrases consécutives d'une même personne.
class TranscriptBlock {
  /// Cree un bloc.
  const TranscriptBlock({
    required this.segment,
    required this.segmentIds,
    this.speaker,
  });

  /// Segment fusionné (horodatage et source du premier, texte de tous).
  final TranscriptSegmentEntity segment;

  /// Segments d'origine, dans l'ordre.
  final List<String> segmentIds;

  /// Interlocuteur du bloc (audio système), null si inconnu.
  final int? speaker;
}

final RegExp _sentenceEnd = RegExp(r'[.!?…]["»”’)]*$');

/// Regroupe les phrases qu'une pause a coupées en plusieurs segments.
///
/// Deux segments consécutifs sont fusionnés s'ils viennent de la même source,
/// du même interlocuteur (ou d'un interlocuteur encore inconnu), que le
/// premier ne se termine pas par une fin de phrase et que le second commence
/// moins de [maxGapMs] après le premier.
List<TranscriptBlock> groupTranscript(
  List<TranscriptSegmentEntity> segments, {
  Map<String, int> speakerLabels = const <String, int>{},
  int maxGapMs = 30000,
}) {
  final List<TranscriptBlock> blocks = <TranscriptBlock>[];
  for (final TranscriptSegmentEntity seg in segments) {
    final int? speaker = speakerLabels[seg.id];
    if (blocks.isNotEmpty) {
      final TranscriptBlock last = blocks.last;
      final bool sameSpeaker =
          speaker == null || last.speaker == null || speaker == last.speaker;
      final bool continues =
          last.segment.source == seg.source &&
          sameSpeaker &&
          !_sentenceEnd.hasMatch(last.segment.text.trim()) &&
          seg.timestampMs - last.segment.timestampMs <= maxGapMs;
      if (continues) {
        blocks[blocks.length - 1] = TranscriptBlock(
          segment: last.segment.copyWith(
            text: '${last.segment.text.trim()} ${seg.text.trim()}',
          ),
          segmentIds: <String>[...last.segmentIds, seg.id],
          speaker: last.speaker ?? speaker,
        );
        continue;
      }
    }
    blocks.add(
      TranscriptBlock(
        segment: seg,
        segmentIds: <String>[seg.id],
        speaker: speaker,
      ),
    );
  }
  return blocks;
}
