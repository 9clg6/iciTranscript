import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';

/// Format commun des transcriptions exportées et copiées.
abstract final class TranscriptFormatter {
  static String sourceLabel(AudioSource source) =>
      source == AudioSource.input ? 'MOI' : 'RÉUNION';

  static String timestamp(int timestampMs) {
    final Duration duration = Duration(milliseconds: timestampMs);
    final String hours = duration.inHours.toString().padLeft(2, '0');
    final String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String plainLine(TranscriptSegmentEntity segment) =>
      '[${timestamp(segment.timestampMs)}] '
      '${sourceLabel(segment.source)}: ${segment.text}';

  static String markdownLine(TranscriptSegmentEntity segment) =>
      '**[${timestamp(segment.timestampMs)}] '
      '${sourceLabel(segment.source)}** — ${segment.text}';
}
