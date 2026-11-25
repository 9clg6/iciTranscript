import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/transcript_line.widget.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/question_answer.widget.dart';
import 'package:ici_transcript/features/shell/presentation/meeting_suggestion.widget.dart';

/// Phrases finies montrées par le panneau de barre de menus.
const int kStatusPanelTranscriptLines = 3;

/// Ce que le panneau de barre de menus (Swift, canal
/// `com.icitranscript/status_panel`) affiche : seulement des String, int,
/// bool, null, List et Map. Contrat détaillé en tête de
/// test/features/status_panel/status_panel_snapshot_test.dart.
Map<String, Object?> statusPanelSnapshot({
  required LiveTranscriptionState live,
  required List<LiveQuestion> questions,
  required MeetingSuggestion? suggestion,
  required bool dictating,
}) {
  final String status = live.finalisingRemaining != null
      ? 'finalising'
      : live.isPaused
      ? 'paused'
      : live.isRecording
      ? 'recording'
      : 'idle';
  return <String, Object?>{
    'status': status,
    'elapsedSeconds': live.duration.inSeconds,
    'finalisingSeconds': live.finalisingRemaining?.inSeconds,
    'title': status == 'idle' ? null : live.sessionTitle,
    'transcript': _transcript(live),
    'question': questions.isEmpty ? null : _question(questions.last),
    'suggestion': suggestion == null ? null : statusPanelSuggestion(suggestion),
    'dictating': dictating,
    // Un seul « Démarrer la note » : celui de la suggestion s'il y en a une.
    'showStart': status == 'idle' && suggestion == null,
    // Seulement s'il y a quelque chose à dire (contrat du panneau inchangé).
    if (!live.storage.isFine) 'storage': _storage(live.storage),
  };
}

/// Place disque telle que le panneau l'affiche.
Map<String, Object?> _storage(RecordingStorage s) => <String, Object?>{
  'level': s.level.name,
  'minutesLeft': s.recordingTimeLeft?.inMinutes,
  'audioCopyFailing': s.audioCopyFailing,
  'unsavedLines': s.unsavedLines,
};

/// Suggestion telle que le panneau l'affiche (`suggestion`, `suggest`).
Map<String, Object?> statusPanelSuggestion(MeetingSuggestion s) =>
    <String, Object?>{
      'kind': s.source.name,
      'title': suggestionTitle(s),
      'detail': suggestionDetail(s),
    };

/// Phrase finie : ni phrase en cours, ni passage provisoire, ni repère
/// (perte ou passage non transcrit).
bool _finished(TranscriptSegmentEntity s) =>
    !s.id.startsWith('current_') &&
    !s.id.endsWith('_pending') &&
    !isTranscriptMarker(s.text);

List<Object?> _transcript(LiveTranscriptionState live) {
  final List<TranscriptSegmentEntity> done = live.segments
      .where(_finished)
      .toList();
  return <Object?>[
    for (final TranscriptSegmentEntity s in done.skip(
      done.length > kStatusPanelTranscriptLines
          ? done.length - kStatusPanelTranscriptLines
          : 0,
    ))
      <String, Object?>{
        'speaker': liveSpeakerLabel(s.source, live.speakerLabels[s.id]),
        'source': s.source.name,
        'text': s.text,
      },
  ];
}

Map<String, Object?> _question(LiveQuestion q) => <String, Object?>{
  'id': q.id,
  'text': q.text,
  'state': q.status.name,
  'answer': answerPlainText(q.answer),
  // Coupée au milieu d'une phrase OU lignes non montrées : pour le panneau,
  // une seule mention « réponse raccourcie » (le contrat n'a qu'une clé).
  'truncated': q.truncated || q.shortened,
  'sources': <Object?>[for (final AnswerSource s in q.sources) s.title],
};
