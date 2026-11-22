import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Borne d'une requête : consignes + messages, en caractères (le modèle
/// local tourne avec un contexte borné).
const int kLlmMaxRequestChars = 10000;

/// Jetons de réponse d'un résumé ou d'un retour du coach. Large : chez
/// certains modèles, la réflexion compte dans cette borne.
const int kLlmAnswerMaxTokens = 4096;

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

const String _coachSystem =
    'You are an English coach. The transcript below is the spoken English '
    'of a non-native speaker during a meeting. Identify the most useful '
    'mistakes and improvements. For each, give the original phrase, a '
    'corrected/improved version, a category among "conjugation", '
    '"vocabulary", "expression" or "grammar", and a SHORT explanation IN '
    'FRENCH. Respond ONLY with a JSON object of the exact shape: '
    '{"overall": string, "corrections": [{"original": string, '
    '"corrected": string, "category": string, "explanation": string}]}. '
    'The "overall" field is a short assessment of the level, in French. '
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
  final int room = _room(_coachSystem, _coachPrefix);
  // ponytail: au-delà de la borne, seule la fin est corrigée (comme avant).
  final String kept = micTranscript.length <= room
      ? micTranscript
      : micTranscript.substring(micTranscript.length - room);
  final String answer = await llm
      .streamChat(_request(_coachSystem, _coachPrefix, kept))
      .join();
  return parseFeedback(answer);
}

/// Lit le retour du coach dans [answer].
EnglishFeedbackEntity parseFeedback(String answer) {
  final int start = answer.indexOf('{');
  final int end = answer.lastIndexOf('}');
  if (start < 0 || end <= start) throw const LlmMalformedAnswerException();
  try {
    final Object? json = jsonDecode(answer.substring(start, end + 1));
    // Un objet sans les champs attendus (`{}`, autre forme) n'est pas un
    // retour vide valable.
    if (json is! Map<String, dynamic> ||
        (json['overall'] is! String && json['corrections'] is! List) ||
        (json['overall'] != null && json['overall'] is! String) ||
        (json['corrections'] != null && json['corrections'] is! List)) {
      throw const LlmMalformedAnswerException();
    }
    return EnglishFeedbackEntity.fromJson(json);
  } on Object {
    throw const LlmMalformedAnswerException();
  }
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
