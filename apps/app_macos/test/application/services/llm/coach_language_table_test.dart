import 'dart:convert';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';

import '../../../helpers/llm_fakes.dart' show ScriptedLlmProvider, requestText;

/// Quelles phrases de l'utilisateur vont au coach (revue de la PR #26).
///
/// Une phrase écartée ne laisse aucune trace : une règle de langue trop
/// stricte fait disparaître en silence de l'anglais ordinaire. Tables
/// d'exemples inventés, phrase par phrase, par le vrai `coachMeeting` :
/// - À CORRIGER : anglais parlé ordinaire, y compris contractions (deux
///   apostrophes), « a », mots qui existent aussi en français (« me »,
///   « on », « son », « pour », « an », « des » comme prénom), sigles en
///   capitales (« EST », « ETA », « LE »), nom propre ou marque française
///   dans une phrase anglaise (« La Poste », « Jean-Pierre du Pont »,
///   « Le Monde »), prénom accentué, réponses courtes avec une vraie faute ;
/// - À ÉCARTER : le franglais épinglé, le français, le français avec une
///   marque anglaise, les interjections.
void main() {
  TranscriptSegmentEntity mine(String text) => TranscriptSegmentEntity(
    id: 'u',
    sessionId: 's1',
    source: AudioSource.input,
    text: text,
    timestampMs: 0,
    createdAt: DateTime(2026, 11, 23, 10),
  );

  Future<bool> sent(String sentence) async {
    final ScriptedLlmProvider llm = ScriptedLlmProvider(
      (LlmChatRequest r, int i) => Stream<String>.value(
        jsonEncode(<String, Object?>{'corrections': <Object>[]}),
      ),
    );
    await coachMeeting(llm, <TranscriptSegmentEntity>[mine(sentence)]);
    return llm.requests.any(
      (LlmChatRequest r) => requestText(r).contains(sentence),
    );
  }

  const List<String> mustBeCoached = <String>[
    "I'm agree with you.",
    'I’m agree with you.',
    "He don't know the answer.",
    'It’s a good idea.',
    "I'd like to add a point.",
    "We're ready for the demo.",
    "That's a fair point.",
    'Can you send me the file?',
    'Me too.',
    "Let's meet on Monday.",
    'My son is sick today.',
    'Could you pour me a coffee?',
    'Pour me some water, please.',
    "It's an option.",
    'Des will join us later.',
    'The EST deadline works for me.',
    'What is the ETA for the release?',
    'The LE team has the numbers.',
    'The La Poste contract is signed.',
    'I met Jean-Pierre du Pont yesterday.',
    'Le Monde wrote about it.',
    'Hélène will send the file.',
    'I am agree.',
    'He don’t know.',
    'We discussed about the budget.',
    'Do you have a minute?',
    'She is in the office.',
    'We need a decision by Friday.',
  ];

  const List<String> mustBeSkipped = <String>[
    'On fait le call with the team.',
    'Je pense que le budget est validé pour la semaine.',
    'Je vous envoie le deck demain.',
    "C'est bon pour moi.",
    'On utilise Slack pour ça.',
    'Merci beaucoup.',
    'OK.',
    'Yes exactly.',
    'Voilà.',
    'Euh…',
    'Bah oui.',
  ];

  group('à corriger (anglais ordinaire)', () {
    for (final String s in mustBeCoached) {
      test('« $s » part au coach', () async {
        expect(await sent(s), isTrue);
      });
    }
  });

  group('à écarter', () {
    for (final String s in mustBeSkipped) {
      test('« $s » ne part pas', () async {
        expect(await sent(s), isFalse);
      });
    }
  });
}
