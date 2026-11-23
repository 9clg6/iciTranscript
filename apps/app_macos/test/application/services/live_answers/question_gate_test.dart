import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/question_gate.dart';

/// Porte de détection (T4, besoin 1) : fonction pure, sans réseau, qui dit si
/// une phrase finalisée est une question à laquelle proposer une réponse.
///
/// API supposée (lib/application/services/live_answers/question_gate.dart) :
/// - `List<String> detectQuestions(TranscriptSegmentEntity segment)` : les
///   phrases-questions du segment, telles qu'écrites (blancs autour retirés),
///   dans l'ordre ; liste vide si aucune. Seule la parole des AUTRES
///   (`AudioSource.output`) déclenche : un segment micro rend toujours [].
/// - Règle choisie (à documenter dans le code) : une phrase finissant par
///   « ? » est candidate si elle n'est pas une formule (tag, politesse,
///   « Quoi ? » seul) et compte au moins `kMinQuestionWords` = 3 mots ; une
///   phrase SANS ponctuation finale (sortie ASR) est candidate si elle
///   commence (après « et / alors / donc / mais / and / so ») par une forme
///   interrogative ; une phrase finissant par « . » ou « ! » ne l'est jamais ;
///   une affirmation suivie d'un tag (« …, d'accord ? », « …, right? ») non
///   plus.
void main() {
  TranscriptSegmentEntity seg(
    String text, {
    AudioSource source = AudioSource.output,
  }) => TranscriptSegmentEntity(
    id: 'seg-1',
    sessionId: 's1',
    source: source,
    text: text,
    timestampMs: 65000,
    createdAt: DateTime(2026, 11, 22, 10),
  );

  group('questions des autres participants : candidates', () {
    const List<String> positives = <String>[
      // Français, ponctué.
      'Est-ce que vous avez prévu une date de livraison ?',
      "Qu'est-ce que vous proposez pour la maintenance ?",
      'Comment vous gérez la sauvegarde des données ?',
      'Pourquoi le budget a augmenté de vingt pour cent ?',
      'Quand est-ce que la migration sera terminée ?',
      'Combien coûte la licence par utilisateur ?',
      'Où sont hébergés les serveurs ?',
      'Qui est responsable du support le week-end ?',
      'Quel est le délai de mise en route ?',
      'Quelle solution recommandez-vous pour la sécurité ?',
      'Quels sont les prérequis techniques ?',
      'Quelles garanties offrez-vous sur la disponibilité ?',
      'Pouvez-vous nous envoyer le devis avant vendredi ?',
      'Avez-vous déjà travaillé avec des banques ?',
      'As-tu reçu le contrat signé ?',
      'Vous avez une démo à nous montrer ?',
      'Et sur la partie mobile, vous comptez faire quoi ?',
      'Savez-vous si le client a validé le cahier des charges ?',
      // Français, sortie ASR sans ponctuation.
      'est-ce que vous avez prévu une date de livraison',
      "qu'est-ce qui bloque la mise en production",
      'peux-tu me rappeler le nom du fournisseur',
      'combien de temps faut-il pour former les équipes',
      'et quand est-ce que vous pouvez commencer',
      // Anglais, ponctué.
      'What is the expected delivery date?',
      'How do you handle data backups?',
      'Why did the budget go up by twenty percent?',
      'When will the migration be finished?',
      'Where are the servers hosted?',
      'Who is in charge of weekend support?',
      'Which plan would you recommend for a team of fifty?',
      'Can you send us the quote before Friday?',
      'Would you be able to start in January?',
      'Do you support single sign-on?',
      'Does the price include training?',
      'Did you get the signed contract?',
      'Are you planning a mobile version?',
      'Is the API rate limited?',
      // Anglais, sortie ASR sans ponctuation.
      'what is the expected delivery date',
      'could you walk us through the onboarding process',
      'how many users can we add on the basic plan',
      'so when do you expect the first release',
      // Affirmation ASR qui commence par un mot interrogatif : candidate à la
      // porte ; le modèle doit la refuser (NO_ANSWER), voir le service.
      'quand on aura fini on livrera',
    ];

    for (final String text in positives) {
      test('« $text » → une question, la phrase elle-même', () {
        expect(detectQuestions(seg(text)), <String>[text]);
      });
    }
  });

  group('formules, politesses et affirmations : jamais candidates', () {
    const List<String> negatives = <String>[
      // Tags et formules de remplissage.
      "D'accord ?",
      'OK ?',
      'Ok?',
      'Okay?',
      'Right?',
      'Tu vois ?',
      'Vous voyez ?',
      "N'est-ce pas ?",
      'Hein ?',
      'You know?',
      'Is it?',
      "Isn't it?",
      'Really?',
      'Vraiment ?',
      'Pardon ?',
      'Sorry?',
      'Allô ?',
      // « Quoi ? » seul.
      'Quoi ?',
      'What?',
      // Salutations.
      'Ça va ?',
      'Comment ça va ?',
      'Comment allez-vous ?',
      'How are you?',
      'How are you doing?',
      // Logistique de réunion.
      "Vous m'entendez ?",
      'Can you hear me?',
      "Tu m'entends ?",
      'Is my screen visible?',
      'Vous voyez mon écran ?',
      // Affirmations qui contiennent un mot interrogatif.
      'Le client qui a signé hier attend la facture.',
      'Quand on aura fini les tests, on livrera.',
      'I know what you mean.',
      "That's how we do it.",
      'Je ne sais pas pourquoi ça plante.',
      'Je vous explique comment fonctionne le module.',
      "We'll see where it goes.",
      'Which is why we moved to the cloud.',
      'When we started the project the scope was smaller.',
      'on verra combien ça coûte la semaine prochaine',
      'What a great demo!',
      'Quelle belle journée !',
      // Rien d'interrogatif.
      'Merci beaucoup pour votre temps.',
      'Thank you so much.',
      'who knows',
      '',
    ];

    for (final String text in negatives) {
      test('« $text » → aucune question', () {
        expect(detectQuestions(seg(text)), isEmpty);
      });
    }
  });

  group('segment de plusieurs phrases', () {
    test('rend la phrase-question, pas tout le segment', () {
      expect(
        detectQuestions(
          seg(
            'Merci pour la présentation. Quel est le prix du module RH ? '
            'On en a besoin vite.',
          ),
        ),
        <String>['Quel est le prix du module RH ?'],
      );
    });

    test('en anglais aussi', () {
      expect(
        detectQuestions(
          seg('Thanks for the demo. How long does the setup take?'),
        ),
        <String>['How long does the setup take?'],
      );
    });

    test('deux questions dans le segment : les deux, dans l\'ordre', () {
      expect(
        detectQuestions(
          seg('Quel est le prix du module ? Et quand pouvez-vous commencer ?'),
        ),
        <String>[
          'Quel est le prix du module ?',
          'Et quand pouvez-vous commencer ?',
        ],
      );
    });

    test('un tag après une affirmation ne fait pas une question', () {
      expect(detectQuestions(seg('On livre en mars, d\'accord ?')), isEmpty);
    });
  });

  group('seule la parole des autres déclenche', () {
    for (final String text in <String>[
      'Est-ce que vous avez prévu une date de livraison ?',
      'est-ce que vous avez prévu une date de livraison',
      'What is the expected delivery date?',
    ]) {
      test('« $text » dit au micro (l\'utilisateur) → rien', () {
        expect(detectQuestions(seg(text, source: AudioSource.input)), isEmpty);
      });
    }
  });
}
