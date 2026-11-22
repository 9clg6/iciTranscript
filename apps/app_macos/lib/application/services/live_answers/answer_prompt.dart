import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart'
    show kLlmAnswerMaxTokens;
import 'package:ici_transcript/application/services/transcript_formatter.dart';

/// Une phrase de la réunion donnée au modèle comme contexte.
typedef ContextLine = ({
  AudioSource source,
  int? speaker,
  int timestampMs,
  String text,
});

/// Consignes du modèle : le contrat de sortie lu par [parseAnswer]. Seul
/// endroit où il est écrit.
const String kLiveAnswerSystemPrompt =
    'You help the user during a live meeting: another participant just asked '
    'a question and you suggest what the user could answer.\n'
    'Rules:\n'
    '- Use only the meeting context and the numbered document excerpts given '
    'below. Never use outside knowledge, never guess a number, a date or a '
    'name.\n'
    '- If they do not contain the answer, or the text is not a question '
    'addressed to the user, reply exactly $kNoAnswerToken and nothing else.\n'
    '- Answer in the language of the question.\n'
    '- Output: one short headline sentence that answers, then at most '
    '$kMaxBullets bullets starting with "- ", one short sentence each. Every '
    'line ends with a period. No preamble, no heading, no bold.\n'
    '- After a sentence that uses an excerpt, cite it with its tag, for '
    'example [S1]. Never cite a tag that is not listed.';

/// Requête de réponse à [question] : contexte récent (déjà fenêtré et
/// borné), extraits numérotés `[S1]`… Jamais le document entier ni l'audio.
LlmChatRequest buildLiveAnswerRequest({
  required String question,
  required ContextLine asked,
  required List<ContextLine> context,
  required List<DocumentExcerpt> excerpts,
}) {
  final StringBuffer b = StringBuffer('Meeting context (oldest first):\n');
  for (final ContextLine l in context) {
    b.writeln(contextLine(l));
  }
  b.writeln();
  if (excerpts.isEmpty) {
    b.writeln("Excerpts from the user's documents: none.");
  } else {
    b.writeln("Excerpts from the user's documents:");
    for (int i = 0; i < excerpts.length; i++) {
      b.writeln('[S${i + 1}] ${excerpts[i].documentTitle}: ${excerpts[i].text}');
    }
  }
  b
    ..writeln()
    ..writeln(
      'Question (${_who(asked)}, at '
      '${TranscriptFormatter.timestamp(asked.timestampMs)}):',
    )
    ..write(question);
  return LlmChatRequest(
    systemPrompt: kLiveAnswerSystemPrompt,
    messages: <LlmMessage>[
      LlmMessage(role: LlmRole.user, content: b.toString()),
    ],
    // Large : chez certains modèles, la réflexion compte dans cette borne ;
    // la tête et trois puces ne doivent jamais être coupées.
    maxTokens: kLlmAnswerMaxTokens,
  );
}

/// « [00:01:05] Speaker 2: texte ».
String contextLine(ContextLine l) =>
    '[${TranscriptFormatter.timestamp(l.timestampMs)}] ${_who(l)}: ${l.text}';

String _who(ContextLine l) => l.source == AudioSource.input
    ? 'User'
    : l.speaker == null
    ? 'Other participant'
    : 'Speaker ${l.speaker! + 1}';
