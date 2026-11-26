import 'dart:convert';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

import 'llm_fakes.dart';

/// Longueur, en caractères, de la plus longue réponse que le fournisseur
/// rend : sonde réelle (mistral-small-latest, max_tokens 4096) coupée à
/// 4 096 jetons, JSON interrompu au caractère 16 000 (`finish_reason:
/// length`). Demander plus de jetons n'en obtient pas plus ici.
const int kProviderAnswerCutChars = 16000;

/// Caractères par jeton de réponse mesurés sur la même sonde
/// (16 000 / 4 096).
const double kAnswerCharsPerToken = 3.9;

const List<String> _templates = <String>[
  'So about the item #, uh, we was thinking that the client don\'t need '
      'the new screen before the launch.',
  'Point #, I mean, the team have already discuss about it and they says '
      'the budget is more bigger now.',
  'For the ticket # we must to finish the tests, because yesterday nobody '
      'have checked the deployment.',
  'And the topic #, you know, I am agree with them but we cannot to change '
      'the plan since the last month.',
];

/// Phrase [i] d'une réunion dense : anglais parlé inventé, hésitant, une
/// faute ou plus par phrase, ~100 caractères, le numéro tôt (deux phrases
/// ne commencent jamais pareil).
String denseSentence(int i) =>
    _templates[i % _templates.length].replaceFirst('#', '$i');

/// Réunion de la note `s1` : [count] phrases de l'utilisateur au micro
/// (`seg-0`…), une par segment, toutes les 5 s.
List<TranscriptSegmentEntity> denseMicMeeting(int count) =>
    <TranscriptSegmentEntity>[
      for (int i = 0; i < count; i++)
        noteSegment(i, denseSentence(i), source: AudioSource.input),
    ];

/// `original` de la correction que le fournisseur factice rend pour
/// [sentence] (le passage fautif : son début).
String coachOriginalOf(String sentence) => sentence.substring(0, 40).trim();

/// Caractères de réponse par caractère de transcription, mesurés sur le
/// vrai fournisseur (mistral-small-latest, anglais parlé dense, 2026-11-26) :
/// ~1 450 caractères → 7 306 caractères de réponse (27 corrections) ;
/// 2 707 → 3 083 jetons (45 corrections, « at most 30 » ignoré). Soit ~5 :
/// une réponse est coupée au-delà de ~3 200 caractères de transcription.
const double kMeasuredAnswerCharsPerChar = 5;

/// Locuteur plus dense que la mesure (plus de fautes par phrase) : un lot
/// de ~1 500 caractères dépasse la réponse, sa moitié tient.
const double kDenserSpeakerAnswerCharsPerChar = 12;

const String _explanation =
    'Accord du verbe avec le sujet : « the team has », « they say » ; '
    'vérifiez chaque verbe conjugué. ';
const String _filler =
    'Reprenez la phrase à voix haute en vérifiant chaque verbe. ';

/// Correction de [sentence] longue de ~[ratio] × (sa longueur + saut de
/// ligne), séparateur compris. ponytail: une seule correction allongée par
/// phrase (le vrai en donne ~2 de ~270 caractères) : même total, et « une
/// correction par phrase » reste vérifiable.
String _correction(String sentence, double ratio) {
  Map<String, String> of(String explanation) => <String, String>{
    'original': coachOriginalOf(sentence),
    'corrected': '${coachOriginalOf(sentence)}, corrected',
    'category': 'grammar',
    'explanation': explanation,
  };
  final int pad =
      (ratio * (sentence.length + 1)).round() -
      2 -
      jsonEncode(of(_explanation)).length;
  final String filler = _filler * (pad ~/ _filler.length + 1);
  return jsonEncode(
    of('$_explanation${filler.substring(0, pad.clamp(0, filler.length))}'),
  );
}

/// Réponse complète (non coupée) du fournisseur factice à [request] : une
/// correction par phrase de [sentences] présente dans la requête, soit
/// ~[answerCharsPerChar] caractères de réponse par caractère de
/// transcription. Ignore toute consigne « at most N » (le vrai l'ignore,
/// mesuré) : seul un lot assez court tient dans la réponse.
String fullCoachAnswer(
  LlmChatRequest request,
  List<String> sentences, {
  double answerCharsPerChar = kMeasuredAnswerCharsPerChar,
}) {
  final String sent = requestText(request);
  final String corrections = <String>[
    for (final String s in sentences)
      if (sent.contains(s)) _correction(s, answerCharsPerChar),
  ].join(', ');
  return '{"overall": "Niveau intermédiaire : à l\'aise à l\'oral, accords '
      'des verbes à revoir.", "corrections": [$corrections]}';
}

/// Fournisseur qui se comporte comme le vrai sur une réunion dense :
/// [fullCoachAnswer], coupée à [kProviderAnswerCutChars] caractères quand
/// elle est plus longue (limite de jetons atteinte). Une requête qui porte
/// [unreadableWith] reçoit toujours une réponse coupée, si courte soit-elle
/// (phrase que le modèle ne sait pas traiter).
ScriptedLlmProvider tokenLimitedCoach(
  List<String> sentences, {
  double answerCharsPerChar = kMeasuredAnswerCharsPerChar,
  String? unreadableWith,
}) => ScriptedLlmProvider((LlmChatRequest r, int i) {
  final String full = fullCoachAnswer(
    r,
    sentences,
    answerCharsPerChar: answerCharsPerChar,
  );
  if (unreadableWith != null && requestText(r).contains(unreadableWith)) {
    return Stream<String>.value(full.substring(0, full.length ~/ 2));
  }
  return Stream<String>.value(
    full.length <= kProviderAnswerCutChars
        ? full
        : full.substring(0, kProviderAnswerCutChars),
  );
});
