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
/// endroit où il est écrit, pour tous les fournisseurs. [language] : langue
/// de la question (« French », « English »), null si inconnue.
String liveAnswerSystemPrompt(String? language) =>
    'You help the user during a live meeting: another participant just asked '
    'a question and you suggest what the user could answer.\n'
    'Rules:\n'
    '- Use only the meeting context and the numbered document excerpts given '
    'below. Never use outside knowledge, never guess a number, a date or a '
    'name. Never give advice, steps or procedures from general knowledge '
    'presented as facts.\n'
    '- If they do not contain the answer, or the text is not a question '
    'addressed to the user, reply exactly $kNoAnswerToken and nothing else.\n'
    '${language == null ? '- Answer in the language of the question.' : '- Answer in $language, the language of the question, even if the context or the excerpts are in another language.'}\n'
    '- Output: one short headline sentence that answers, then at most '
    '$kMaxBullets bullets starting with "- ", one short sentence each. Every '
    'line ends with a period. No preamble, no title, no heading, no bold.\n'
    '- After a sentence that uses an excerpt, cite it with its tag, for '
    'example [S1]. Never cite a tag that is not listed, never cite a time.';

/// Langue de [question] (« French » ou « English ») d'après ses mots ;
/// null si rien ne permet de trancher.
// ponytail: deux langues comptées sur des mots fréquents ; une 3e langue
// demandera un vrai détecteur.
String? questionLanguage(String question) {
  final List<String> words = question
      .toLowerCase()
      .split(RegExp(r"[^\p{L}']+", unicode: true))
      .expand((String w) => w.split("'"))
      .where((String w) => w.isNotEmpty)
      .toList();
  final int fr =
      words.where(_frenchWords.contains).length +
      (RegExp('[àâçéèêëîïôûùüœ]').hasMatch(question.toLowerCase()) ? 2 : 0);
  final int en = words.where(_englishWords.contains).length;
  if (fr == en) return null;
  return fr > en ? 'French' : 'English';
}

const Set<String> _frenchWords = <String>{
  'le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'est', 'et', 'que', //
  'qui', 'quel', 'quelle', 'quels', 'quelles', 'combien', 'comment', //
  'pourquoi', 'quand', 'tu', 'vous', 'on', 'nous', 'ce', 'pour', 'sur', //
  'avec', 'il', 'elle', 'sais', 'qu', 'c', 'l', 'd', 'en', 'pas', //
};

const Set<String> _englishWords = <String>{
  'the', 'is', 'are', 'was', 'were', 'do', 'does', 'did', 'what', 'how', //
  'why', 'when', 'where', 'who', 'which', 'we', 'you', 'our', 'can', //
  'could', 'would', 'will', 'have', 'has', 'of', 'to', 'for', 'on', 'it', //
  'much', 'many', 'that', 'this', 'with', 'and', 'any', //
};

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
      b.writeln(
        '[S${i + 1}] ${excerpts[i].documentTitle}: ${excerpts[i].text}',
      );
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
    systemPrompt: liveAnswerSystemPrompt(questionLanguage(question)),
    messages: <LlmMessage>[
      LlmMessage(role: LlmRole.user, content: b.toString()),
    ],
    // Large : chez certains modèles, la réflexion compte dans cette borne ;
    // la tête et trois puces ne doivent jamais être coupées.
    maxTokens: kLlmAnswerMaxTokens,
    // Réponse courte en direct : la latence prime (effort bas chez Claude).
    preferLowLatency: true,
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
