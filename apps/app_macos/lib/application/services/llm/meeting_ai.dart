import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart'
    show isTranscriptMarker;

/// Borne d'une requête : consignes + messages, en caractères (le modèle
/// local tourne avec un contexte borné).
const int kLlmMaxRequestChars = 10000;

/// Jetons de réponse d'un résumé ou d'un retour du coach. Large : chez
/// certains modèles, la réflexion compte dans cette borne.
const int kLlmAnswerMaxTokens = 4096;

/// Corrections au plus par réponse du coach : borne la réponse (≤ 400
/// caractères chacune) sous [kLlmAnswerMaxTokens], quel que soit le texte.
const int kCoachMaxCorrections = 30;

/// Transcription au plus par requête du coach : c'est la place de la RÉPONSE
/// qui limite, pas celle de la requête. Sondes réelles : 9 397 caractères
/// coupés à 4096 jetons ; 2 707 caractères donnent 3 083 jetons et 45
/// corrections malgré « at most 30 » (~4,3 caractères de réponse par
/// caractère de transcription). 1 500 caractères : ~1,7 k jetons, marge > 2.
const int kCoachBatchChars = 1500;

const String _summarySystem =
    'Tu es un assistant qui résume des réunions en français. Produis un '
    'résumé clair et concis : 1 phrase de contexte, puis 4 à 8 puces '
    '(points clés, décisions, actions). Réponds uniquement avec le résumé, '
    'sans préambule.';

const String _partSystem =
    'Tu résumes une partie d\'une longue réunion, en français. Donne en '
    'quelques puces les points clés, décisions et actions de cette partie, '
    'sans préambule.';

const String _mergeSystem =
    'Tu reçois, dans l\'ordre, les résumés des parties successives d\'une '
    'réunion. Produis le résumé de l\'ensemble en français : 1 phrase de '
    'contexte, puis 4 à 8 puces (points clés, décisions, actions). Réponds '
    'uniquement avec le résumé, sans préambule.';

final String _coachSystem =
    'You are an English coach. The transcript below is the spoken English '
    'of a non-native speaker during a meeting. Identify the most useful '
    'mistakes and improvements. For each, give the original phrase, a '
    'corrected/improved version, a category among "conjugation", '
    '"vocabulary", "expression" or "grammar", and a SHORT explanation IN '
    'FRENCH. Respond ONLY with a JSON object of the exact shape: '
    '{"overall": string, "corrections": [{"original": string, '
    '"corrected": string, "category": string, "explanation": string}]}. '
    'The "overall" field is a short assessment of the level, in French. '
    'Give at most $kCoachMaxCorrections corrections, the most useful ones. '
    'Do not invent mistakes: if a sentence is correct, skip it.';

const String _transcriptPrefix = 'Transcription de la réunion :\n\n';
const String _coachPrefix = 'Transcript:\n\n';

/// Résumé de [transcript], émis au fil de l'eau (morceaux de la synthèse).
///
/// Court : une requête qui contient tout. Long : map-reduce, chaque
/// passage résumé à part (requêtes d'au plus [kLlmMaxRequestChars]), puis
/// les résumés fusionnés, par lots si besoin, jusqu'à une synthèse finale.
Stream<String> summarizeMeeting(LlmProvider llm, String transcript) async* {
  if (_fits(_summarySystem, _transcriptPrefix, transcript)) {
    yield* llm.streamChat(
      _request(_summarySystem, _transcriptPrefix, transcript),
    );
    return;
  }
  final List<String> parts = _split(
    transcript,
    _room(_partSystem, _prefixOfPart(9999, 9999)),
  );
  List<String> notes = <String>[];
  for (int i = 0; i < parts.length; i++) {
    notes.add(
      await llm
          .streamChat(
            _request(_partSystem, _prefixOfPart(i + 1, parts.length), parts[i]),
          )
          .join(),
    );
    // Rien à afficher encore, mais l'écouteur qui annule (note fermée)
    // arrête ici, entre deux requêtes.
    yield '';
  }
  const String mergePrefix = 'Résumés des parties, dans l\'ordre :\n\n';
  final int room = _room(_mergeSystem, mergePrefix);
  // Fusion par lots tant que l'ensemble dépasse la borne.
  while (notes.join('\n\n').length > room) {
    final List<String> batches = _split(
      notes.join('\n\n'),
      room,
      separator: '\n\n',
    );
    if (batches.length >= notes.length) {
      // Chaque résumé tient seul mais pas deux ensemble : on les raccourcit.
      notes = <String>[
        for (final String n in notes)
          n.substring(
            0,
            n.length.clamp(0, (room - 2 * notes.length) ~/ notes.length),
          ),
      ];
      break;
    }
    final List<String> merged = <String>[];
    for (final String batch in batches) {
      merged.add(
        await llm.streamChat(_request(_mergeSystem, mergePrefix, batch)).join(),
      );
      yield '';
    }
    notes = merged;
  }
  yield* llm.streamChat(
    _request(_mergeSystem, mergePrefix, notes.join('\n\n')),
  );
}

/// Retour du coach d'anglais sur [micTranscript] (parole de l'utilisateur).
///
/// Le JSON peut être entouré de texte ou d'un bloc ```json. Absent, coupé ou
/// d'une autre forme : [LlmMalformedAnswerException].
Future<EnglishFeedbackEntity> coachEnglish(
  LlmProvider llm,
  String micTranscript,
) async {
  final int room = _coachRoom();
  // ponytail: au-delà de la borne, seule la fin est corrigée (comme avant).
  final String kept = micTranscript.length <= room
      ? micTranscript
      : micTranscript.substring(micTranscript.length - room);
  final String answer = await llm
      .streamChat(_request(_coachSystem, _coachPrefix, kept))
      .join();
  return parseFeedback(answer);
}

/// Lit le retour du coach dans [answer] : seul lecteur, pour tous les
/// fournisseurs.
///
/// Objet JSON (entouré de texte ou d'un bloc ```json) ou liste de
/// corrections : lu. Pas de JSON mais une phrase « rien à corriger » (un
/// petit modèle respecte rarement le contrat) : retour vide. Sinon (vide,
/// texte sans rapport, JSON coupé, objet d'une autre forme) :
/// [LlmMalformedAnswerException].
EnglishFeedbackEntity parseFeedback(String answer) {
  final Object? json = _firstJson(answer);
  try {
    if (json is List) {
      return EnglishFeedbackEntity(
        corrections: <EnglishCorrectionEntity>[
          for (final Object? c in json)
            EnglishCorrectionEntity.fromJson(c! as Map<String, dynamic>),
        ],
      );
    }
    if (json is Map<String, dynamic>) {
      // Un objet sans les champs attendus (`{}`, autre forme) n'est pas un
      // retour vide valable.
      if ((json['overall'] is! String && json['corrections'] is! List) ||
          (json['overall'] != null && json['overall'] is! String) ||
          (json['corrections'] != null && json['corrections'] is! List)) {
        throw const LlmMalformedAnswerException();
      }
      return EnglishFeedbackEntity.fromJson(json);
    }
  } on Object {
    throw const LlmMalformedAnswerException();
  }
  if (_nothingToCorrect.hasMatch(answer)) return const EnglishFeedbackEntity();
  throw const LlmMalformedAnswerException();
}

/// JSON de [answer] : la liste si elle s'ouvre avant l'objet et se lit
/// (« [] », liste de corrections), sinon l'objet ; null si aucun. Un objet
/// illisible (coupé) rend un objet vide, donc une réponse illisible.
Object? _firstJson(String answer) {
  final int brace = answer.indexOf('{');
  final int bracket = answer.indexOf('[');
  if (bracket >= 0 && (brace < 0 || bracket < brace)) {
    final Object? list = _decode(answer, bracket, answer.lastIndexOf(']'));
    if (list is List) return list;
  }
  final int end = answer.lastIndexOf('}');
  if (brace < 0 || end <= brace) return null;
  return _decode(answer, brace, end) ?? const <String, dynamic>{};
}

Object? _decode(String text, int start, int end) {
  if (end <= start) return null;
  try {
    return jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    return null;
  }
}

final RegExp _nothingToCorrect = RegExp(
  r"rien à corriger|aucune (correction|erreur|faute)|pas d'erreur|"
  r'no (corrections?|mistakes?|errors?)\b|nothing to correct|'
  r'\bis (perfectly |already |entirely )?correct\b',
  caseSensitive: false,
);

/// Une phrase à corriger : segment (ou morceau d'un segment trop long),
/// texte, heure dans la note.
typedef CoachLine = ({String id, String text, int atMs});

/// Phrase que le coach peut corriger : dite au micro par l'utilisateur, pas
/// un repère, en anglais (règle de [isSpokenEnglish]).
bool isCoachable(TranscriptSegmentEntity s) =>
    s.source == AudioSource.input &&
    !isTranscriptMarker(s.text) &&
    isSpokenEnglish(s.text);

/// Anglais : au moins un mot-outil anglais et au plus UN mot-outil
/// français. Un seul ne suffit pas à écarter une phrase : sigles (« EST »,
/// « LE »), noms et marques (« La Poste », « du Pont », « Le Monde »),
/// homographes (« pour me a coffee », « Des will… ») ; le franglais en a
/// deux (« On fait le call… »). « on », « a » ne comptent pas comme
/// français. Pas de veto par `questionLanguage` : un accent (« Hélène »)
/// le fait pencher vers le français. « OK », « yes », « exactly » sont des
/// interjections, pas des mots-outils.
// ponytail: listes de mots fréquents ; un vrai détecteur si une 3e langue
// arrive.
bool isSpokenEnglish(String text) {
  final List<String> words = text
      .toLowerCase()
      .split(RegExp(r"[^\p{L}']+", unicode: true))
      .expand((String w) => w.split("'"))
      .where((String w) => w.isNotEmpty)
      .toList();
  return words.any(_englishFunctionWords.contains) &&
      words.where(_frenchFunctionWords.contains).length < 2;
}

const Set<String> _englishFunctionWords = <String>{
  'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', //
  'them', 'my', 'your', 'his', 'its', 'our', 'their', 'this', 'that', //
  'these', 'those', 'the', 'a', 'an', 'am', 'is', 'are', 'was', 'were', //
  'be', 'been', 'do', 'does', 'did', 'have', 'has', 'had', 'will', //
  'would', 'can', 'could', 'should', 'shall', 'may', 'might', 'must', //
  'of', 'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'about', //
  'so', 'but', 'and', 'or', 'if', 'not', 'there', 'what', 'how', 'why', //
  'when', 'where', 'who', 'which', //
};

// Sans les homographes anglais (« on », « a », « as », « son », « car »,
// « ai »…).
const Set<String> _frenchFunctionWords = <String>{
  'le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'est', 'et', 'que', //
  'qui', 'quel', 'quelle', 'quels', 'quelles', 'combien', 'comment', //
  'pourquoi', 'quand', 'je', 'tu', 'il', 'elle', 'ils', 'elles', 'nous', //
  'vous', 'ce', 'ça', 'pour', 'sur', 'avec', 'dans', 'en', 'pas', 'ne', //
  'mais', 'ou', 'donc', 'au', 'aux', 'se', 'sa', 'ses', 'mon', 'ma', //
  'mes', 'ton', 'ta', 'notre', 'votre', 'leur', 'qu', 'fait', 'faire', //
  'suis', 'sont', 'va', 'vais', 'très', 'oui', 'voilà', //
};

/// Phrases corrigeables de [segments], hors [skip] (déjà corrigées en
/// direct).
List<TranscriptSegmentEntity> coachableLines(
  List<TranscriptSegmentEntity> segments, {
  Set<String> skip = const <String>{},
}) => <TranscriptSegmentEntity>[
  for (final TranscriptSegmentEntity s in segments)
    if (!skip.contains(s.id) && isCoachable(s)) s,
];

/// Lots de [lines] : chaque requête tient dans [kLlmMaxRequestChars]
/// (consignes comprises) et au plus [kCoachBatchChars] de texte, chaque
/// phrase dans exactement un lot ; une phrase plus longue que la place est
/// coupée en morceaux.
List<List<CoachLine>> coachBatches(List<TranscriptSegmentEntity> lines) {
  final int room = _coachRoom();
  final List<List<CoachLine>> batches = <List<CoachLine>>[];
  List<CoachLine> current = <CoachLine>[];
  int used = 0;
  for (final TranscriptSegmentEntity s in lines) {
    final String text = s.text.trim();
    for (int i = 0; i < text.length; i += room) {
      final String part = text.substring(i, (i + room).clamp(0, text.length));
      final int cost = part.length + (current.isEmpty ? 0 : 1);
      if (used + cost > room) {
        batches.add(current);
        current = <CoachLine>[];
        used = 0;
      }
      used += part.length + (current.isEmpty ? 0 : 1);
      current.add((id: s.id, text: part, atMs: s.timestampMs));
    }
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// Requête du coach pour [batch] ; [preferLowLatency] seulement en direct.
LlmChatRequest coachRequest(
  List<CoachLine> batch, {
  bool preferLowLatency = false,
}) => LlmChatRequest(
  systemPrompt: _coachSystem,
  messages: <LlmMessage>[
    LlmMessage(
      role: LlmRole.user,
      content: '$_coachPrefix${batch.map((CoachLine l) => l.text).join('\n')}',
    ),
  ],
  maxTokens: kLlmAnswerMaxTokens,
  preferLowLatency: preferLowLatency,
);

/// Corrections de [feedback], chacune à l'heure de la phrase de [batch] qui
/// contient son `original` (sinon sans heure).
List<EnglishCorrectionEntity> timedCorrections(
  EnglishFeedbackEntity feedback,
  List<CoachLine> batch,
) => <EnglishCorrectionEntity>[
  for (final EnglishCorrectionEntity c in feedback.corrections)
    c.copyWith(timestampMs: _timeOf(c.original, batch)),
];

int? _timeOf(String original, List<CoachLine> batch) {
  final String needle = original.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final CoachLine l in batch) {
    if (l.text.toLowerCase().contains(needle)) return l.atMs;
  }
  return null;
}

/// Coach anglais d'une note : phrases corrigeables de [segments] (hors
/// [skipSegmentIds]), par lots bornés, l'un après l'autre (le modèle local
/// ne sert qu'une requête à la fois).
///
/// Un lot en échec ne fait pas tout échouer : ses phrases vont dans
/// `unanalyzedSegmentIds`. Tous en échec : l'erreur du dernier remonte.
/// Rien à corriger : retour vide, aucune requête.
///
/// [shouldStop] est lu avant chaque lot : vrai (un enregistrement démarre,
/// une génération locale retarderait sa transcription), le lot en cours a
/// fini et compte, le reste est noté non analysé, sans erreur.
Future<EnglishFeedbackEntity> coachMeeting(
  LlmProvider llm,
  List<TranscriptSegmentEntity> segments, {
  Set<String> skipSegmentIds = const <String>{},
  bool Function()? shouldStop,
}) async {
  if (coachableLines(segments).isEmpty) {
    return const EnglishFeedbackEntity(nothingToAnalyse: true);
  }
  final List<List<CoachLine>> batches = coachBatches(
    coachableLines(segments, skip: skipSegmentIds),
  );
  final List<EnglishCorrectionEntity> corrections = <EnglishCorrectionEntity>[];
  final Set<String> unanalyzed = <String>{};
  String? overall;
  Object? lastError;
  int failed = 0;
  int sent = 0;
  for (final List<CoachLine> batch in batches) {
    if (shouldStop?.call() ?? false) {
      unanalyzed.addAll(batch.map((CoachLine l) => l.id));
      continue;
    }
    sent++;
    try {
      final EnglishFeedbackEntity part = parseFeedback(
        await llm.streamChat(coachRequest(batch)).join(),
      );
      corrections.addAll(timedCorrections(part, batch));
      if (overall == null && (part.overall ?? '').isNotEmpty) {
        overall = part.overall;
      }
    } on Object catch (e) {
      lastError = e;
      failed++;
      unanalyzed.addAll(batch.map((CoachLine l) => l.id));
    }
  }
  if (sent > 0 && failed == sent) throw lastError!;
  return EnglishFeedbackEntity(
    corrections: corrections,
    overall: overall,
    unanalyzedSegmentIds: unanalyzed.toList(),
  );
}

/// Réponse probablement coupée (limite de jetons, refus) : vide, ou
/// dernière ligne qui n'est ni une puce ni un intertitre et ne finit pas
/// par . ! ? … » ou ). Une liste à puces sans point final est complète.
bool looksTruncated(String answer) {
  final List<String> lines = answer
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return true;
  final String last = lines.last;
  final bool bullet = RegExp(r'^([-*•]|\d+[.)])\s').hasMatch(last);
  final bool heading =
      last.startsWith('#') ||
      (last.startsWith('**') && last.endsWith('**') && last.length > 4);
  return !bullet && !heading && !RegExp(r'[.!?…»)]$').hasMatch(last);
}

String _prefixOfPart(int i, int n) =>
    'Partie $i sur $n de la transcription de la réunion :\n\n';

LlmChatRequest _request(String system, String prefix, String text) =>
    LlmChatRequest(
      systemPrompt: system,
      messages: <LlmMessage>[
        LlmMessage(role: LlmRole.user, content: '$prefix$text'),
      ],
      maxTokens: kLlmAnswerMaxTokens,
    );

/// Place laissée au texte dans une requête (consignes, préfixe et saut de
/// ligne qui les sépare compris).
int _room(String system, String prefix) =>
    kLlmMaxRequestChars - system.length - prefix.length - 1;

int _coachRoom() {
  final int room = _room(_coachSystem, _coachPrefix);
  return room < kCoachBatchChars ? room : kCoachBatchChars;
}

bool _fits(String system, String prefix, String text) =>
    text.length <= _room(system, prefix);

/// Coupe [text] en morceaux d'au plus [room] caractères, entre deux
/// [separator] (une ligne de transcription n'est jamais coupée, sauf si
/// elle dépasse seule la borne).
List<String> _split(String text, int room, {String separator = '\n'}) {
  final List<String> pieces = <String>[];
  String current = '';
  for (final String unit in text.split(separator)) {
    for (int i = 0; i < unit.length || i == 0; i += room) {
      final String part = unit.substring(i, (i + room).clamp(0, unit.length));
      if (current.isEmpty) {
        current = part;
      } else if (current.length + separator.length + part.length <= room) {
        current = '$current$separator$part';
      } else {
        pieces.add(current);
        current = part;
      }
    }
  }
  if (current.isNotEmpty) pieces.add(current);
  return pieces;
}

/// [kept] puis les corrections de [added] qui n'y sont pas déjà (même
/// original et même correction, casse et blancs ignorés).
List<EnglishCorrectionEntity> mergeCorrections(
  List<EnglishCorrectionEntity> kept,
  List<EnglishCorrectionEntity> added,
) {
  String key(EnglishCorrectionEntity c) =>
      '${c.original.trim().toLowerCase()}→${c.corrected.trim().toLowerCase()}';
  final Set<String> seen = kept.map(key).toSet();
  return <EnglishCorrectionEntity>[
    ...kept,
    for (final EnglishCorrectionEntity c in added)
      if (seen.add(key(c))) c,
  ];
}
