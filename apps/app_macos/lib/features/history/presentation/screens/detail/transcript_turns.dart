import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';

/// Tour de parole : phrases consécutives d'une même voix.
class TranscriptTurn {
  /// Crée un tour.
  const TranscriptTurn({
    required this.source,
    required this.startMs,
    required this.paragraphs,
    this.speaker,
  });

  /// Micro (toi) ou audio système (l'autre côté de l'appel).
  final AudioSource source;

  /// Interlocuteur diarisé (audio système), null si inconnu.
  final int? speaker;

  /// Début du tour, depuis le début de la note.
  final int startMs;

  /// Blocs de texte du tour, dans l'ordre.
  final List<String> paragraphs;
}

/// Regroupe la transcription en tours de parole.
///
/// Les phrases coupées par une pause sont d'abord recollées
/// ([groupTranscript]), puis les blocs consécutifs d'une même voix forment un
/// tour. Un segment de l'audio système prend l'interlocuteur diarisé dont le
/// tour contient son horodatage.
// ponytail: horodatage des segments et temps de la diarisation comparés tels
// quels (même origine : début de l'enregistrement) ; une pause pendant la
// session les décale, recalage à faire si la diarisation le signale.
List<TranscriptTurn> groupTurns(
  List<TranscriptSegmentEntity> segments,
  List<SpeakerTurn> speakers,
) {
  final Map<String, int> labels = <String, int>{
    for (final TranscriptSegmentEntity s in segments)
      if (s.source == AudioSource.output)
        if (_speakerAt(speakers, s.timestampMs) case final int n) s.id: n,
  };
  final List<TranscriptTurn> turns = <TranscriptTurn>[];
  for (final TranscriptBlock b in groupTranscript(
    segments,
    speakerLabels: labels,
  )) {
    final TranscriptTurn? last = turns.isEmpty ? null : turns.last;
    final String text = b.segment.text.trim();
    if (last != null &&
        last.source == b.segment.source &&
        last.speaker == b.speaker) {
      last.paragraphs.add(text);
      continue;
    }
    turns.add(
      TranscriptTurn(
        source: b.segment.source,
        speaker: b.speaker,
        startMs: b.segment.timestampMs,
        paragraphs: <String>[text],
      ),
    );
  }
  return turns;
}

int? _speakerAt(List<SpeakerTurn> speakers, int timestampMs) {
  final double t = timestampMs / 1000;
  for (final SpeakerTurn s in speakers) {
    if (t >= s.start && t < s.end) return s.speaker;
  }
  return null;
}
