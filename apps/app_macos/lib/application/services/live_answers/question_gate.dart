import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart'
    show fold;

/// Mots minimum d'une question candidate (« Quoi ? », « Tu vois ? » exclus).
const int kMinQuestionWords = 3;

/// Phrases-questions de [segment] auxquelles proposer une réponse, dans
/// l'ordre, telles qu'écrites. Fonction pure, sans réseau.
///
/// Règle :
/// - seule la parole des autres (`AudioSource.output`) déclenche ;
/// - le segment est coupé en phrases après « . ! ? … » ;
/// - une phrase finissant par « ? » est candidate si elle compte au moins
///   [kMinQuestionWords] mots et n'est ni une salutation, ni de la
///   logistique de réunion (« Vous m'entendez ? »), ni une affirmation
///   suivie d'un tag de remplissage (« …, d'accord ? ») ; suivie d'un tag
///   de confirmation (« …, right? », « …, non ? »), si ;
/// - une phrase sans ponctuation finale (sortie ASR) est candidate si elle
///   compte au moins [kMinQuestionWords] mots et commence, après
///   « et / alors / donc / mais / and / so », par une forme interrogative ;
/// - une phrase finissant par « . », « ! » ou « … » ne l'est jamais.
///
/// Le modèle refuse ensuite (NO_ANSWER) ce qui n'est pas une vraie question.
List<String> detectQuestions(TranscriptSegmentEntity segment) {
  if (segment.source != AudioSource.output) return const <String>[];
  return <String>[
    for (final String s in segment.text.split(_sentenceBreak))
      if (s.trim() case final String t when _isQuestion(t)) t,
  ];
}

final RegExp _sentenceBreak = RegExp(r'(?<=[.!?…])\s+');
final RegExp _endsWithQuestionMark = RegExp(r'\?["»”’)\s]*$');
final RegExp _endsWithOtherStop = RegExp(r'[.!…]["»”’)\s]*$');
final RegExp _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isQuestion(String sentence) {
  if (sentence.split(RegExp(r'\s+')).where(_word.hasMatch).length <
      kMinQuestionWords) {
    return false;
  }
  final String plain = _plain(sentence);
  if (_formula.hasMatch(plain)) return false;
  if (_endsWithQuestionMark.hasMatch(sentence)) {
    return !_tagAfterStatement.hasMatch(sentence.replaceAll('’', "'"));
  }
  if (_endsWithOtherStop.hasMatch(sentence)) return false;
  return _interrogativeStart.hasMatch(
    plain.replaceFirst(_leadingConnector, ''),
  );
}

/// Minuscules sans accent ni ponctuation (apostrophes et traits d'union
/// gardés), blancs réduits.
String _plain(String s) => fold(s)
    .replaceAll(RegExp(r"[’‘]"), "'")
    .replaceAll(RegExp(r"[^\p{L}\p{N}'\- ]", unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final RegExp _leadingConnector = RegExp(r'^((et|alors|donc|mais|and|so) )+');

/// Salutations et logistique de réunion (sur le texte [_plain]).
final RegExp _formula = RegExp(
  r"^((comment )?ca va|comment allez-vous|how are you( doing)?|how's it going)$"
  r"|m'entend|hear me|my screen|mon ecran|ton ecran|votre ecran|see my|"
  r"voir mon|on mute|en sourdine|you're muted",
);

/// « …, d'accord ? », « …, tu vois ? » : un tag de remplissage après une
/// affirmation. Un tag qui demande confirmation (« …, right? », « …, isn't
/// it? », « …, non ? », « …, n'est-ce pas ? ») fait, lui, une question.
final RegExp _tagAfterStatement = RegExp(
  r",\s*(d'accord|ok|okay|hein|tu vois|vous voyez|you know|yes|oui)\s*\?",
  caseSensitive: false,
);

/// Forme interrogative en tête de phrase (texte [_plain]).
final RegExp _interrogativeStart = RegExp(
  r"^(est-ce|qu'est-ce|quel|quelle|quels|quelles|comment|pourquoi|quand|"
  r"combien|qui|ou est|ou sont|"
  r"\p{L}+-(t-)?(je|tu|il|elle|on|nous|vous|ils|elles)\b|"
  r"what|how|why|when|where|who|which|can|could|would|will|do|does|did|"
  r"are|is|should|shall|have|has|may)\b",
  unicode: true,
);
