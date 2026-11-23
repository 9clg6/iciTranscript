import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/question_gate.dart';

/// Porte de détection contre des phrases ENREGISTRÉES (sonde du 2026-11-23,
/// contenu inventé) : questions dites à voix haute (texte de référence et
/// sortie ASR réelle), et phrases de l'audio système des journaux de la
/// sonde (792 phrases, 0 faux positif : un échantillon de 40 reste négatif).
///
/// Règle choisie : une affirmation suivie d'un tag qui demande confirmation
/// (« right? », « isn't it? », « non ? », « n'est-ce pas ? ») est une question
/// (la sonde l'a manquée : « That number comes from last month, right? »).
/// Le tag seul reste une formule ; « d'accord ? », « ok ? », « tu vois ? »
/// après une affirmation restent du remplissage (inchangé).
void main() {
  TranscriptSegmentEntity seg(String text) => TranscriptSegmentEntity(
    id: 'seg-1',
    sessionId: 's1',
    source: AudioSource.output,
    text: text,
    timestampMs: 65000,
    createdAt: DateTime(2026, 11, 22, 10),
  );

  group('question avec tag de confirmation : détectée', () {
    for (final String text in <String>[
      'That number comes from last month, right?',
      "The deadline is the end of the month, isn't it?",
      'On livre le lot 1 en mars, non ?',
      "Le budget est déjà validé, n'est-ce pas ?",
    ]) {
      test('« $text »', () {
        expect(detectQuestions(seg(text)), <String>[text]);
      });
    }

    for (final String text in <String>[
      'Right?',
      "Isn't it?",
      'Non ?',
      "N'est-ce pas ?",
      "On livre en mars, d'accord ?",
      'On livre en mars, tu vois ?',
    ]) {
      test('« $text » : formule, pas une question', () {
        expect(detectQuestions(seg(text)), isEmpty);
      });
    }
  });

  group('questions dites à voix haute pendant la sonde (référence et ASR)', () {
    for (final String text in <String>[
      'Est-ce que tu as reçu le devis du traiteur ?',
      'Est-ce que tu as reçu le devis du traiteur?',
      'Tu as reçu le devis du traiteur ?',
      'Tu as reçu le devis du traiteur?',
      'Quand est-ce que la nouvelle version sort ?',
      'Quand est-ce que la nouvelle version sort?',
      'Combien de personnes participent au pilote ?',
      'Combien de personnes participent au pilote?',
      'On part sur quelle date pour la recette ?',
      'On part sur quelle date pour la recette?',
      'Pourquoi le correctif n\'est pas encore en production ?',
      'Pourquoi le correctif n\'est pas encore en production?',
      'Vous pensez que le budget tiendra jusqu\'à la fin de l\'année ?',
      'Vous pensez que le budget tiendra jusqu\'à la fin de l\'année?',
      'Qui s\'occupe du transport pour le séminaire ?',
      'Et le contrat, il se termine quand ?',
      'Et le contrat, il se termine quand?',
      'C\'est toi qui prépares la démo de jeudi ?',
      'C\'est toi qui prépare la démo de jeudi?',
      'Peux-tu me rappeler le montant de l\'acompte ?',
      'Peux-tu me rappeler le montant de la compte?',
      'Ça coûte combien par utilisateur, la nouvelle offre ?',
      'Quel est le délai de préavis prévu dans le contrat ?',
      'Quel est le délai de préavis prévu dans le contrat?',
      'Tu sais où en est la migration des données ?',
      'Tu sais où on est l\'adaptation des données?',
      'Alors, on valide le planning ou pas ?',
      'Alors, on valide le planning ou pas?',
      'Do you know when the new version ships?',
      'You already sent the report to the team?',
      'How many parking spaces did we get?',
      'What\'s the notice period on the current lease?',
      'Can you remind me who owns the pipeline cleanup?',
      'Why is the response time so high on Mondays?',
      'So the move is still planned for September?',
      'Is the budget for the furniture approved yet?',
      'Where are we with the warehouse migration?',
      'And the chatbot pilot, how is it going so far?',
      'Which supplier did we pick for the desks?',
      'Have we decided who gets a parking space?',
      'Any idea how long we keep the raw event data?',
      'Would it make sense to extend the pilot to another team?',
      'That number comes from last month, right?',
    ]) {
      test('« $text » : détectée', () {
        expect(detectQuestions(seg(text)), isNotEmpty);
      });
    }
  });

  group('audio système enregistré : aucun faux positif', () {
    for (final String text in <String>[
      'The teacher moved the wooden fence during the village fair, and then the gardener photographed the round fountain without telling anyone.',
      'Le jardinier a déplacé la cabane sans prévenir personne, puis le jardinier a décoré la cabane avant la pluie du soir.',
      'La gardienne a déplacé la fontaine ronde sous un ciel gris, puis la voisine a déplacé le kiosque à journaux pendant la fête du village.',
      'La Mega Reparer est le kiosque à journaux malgré le vent froid, puis la musicienne a réparé le kiosque à journaux au lever du soleil.',
      'The librarian painted the wooden fence despite the cold wind, and then the mayor tidied the wooden fence before the evening rain.',
      'Le jardinier a photographié le lavoir au lever du soleil, puis la musicienne a nettoyé la fontaine ronde sous un ciel gris.',
      'My neighbor moved the small cabin for the start of school, and then the postman tidied the green bench before the evening rain.',
      'Le maire a déplacé la cabane sous un ciel gris, puis le facteur a mesuré le kiosque à journaux pour la rentrée des classes.',
      'The baker painted the small cabin without telling anyone, and then the librarian cleaned the round fountain with a lot of patience.',
      'Le libraire a photographié la serre avec beaucoup de patience, puis le libraire a nettoyé la cabane sous un ciel gris.',
      'La musicienne a basuré la fontaine ronde au lever du soleil, puis la musicienne a réparé le banc vert pour la rentrée des classes.',
      'The postman measured the green bench at sunrise, and then the baker repaired the stone wall despite the cold wind.',
      'La voisine a déplacé la fontaine haute pendant la fête du village, puis le facteur a photographié le lavoir avec beaucoup de patience.',
      'Le facteur a repris la cabane sous un ciel gris, puis le libraire a rangé la serre avec beaucoup de patience.',
      'My neighbor tidied the wooden fence for the start of school, and then the mayor repaired the round fountain despite the cold wind.',
      'La Mega Photo vacille le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
      'Le biker a nettoyé le portail avec beaucoup de patience, puis la musicienne a décoré le lavoir avec beaucoup de patience.',
      'The mayor cleaned the old greenhouse under a gray sky, and then my neighbor photographed the small cabin before the evening rain.',
      'The GAGNA measured the stone wall with a lot of patience, and then the mayor moved the garden gate with a lot of patience.',
      'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
      'La gardienne a photographié le portail avec beaucoup de patience, puis le jardinier a repeint la fontaine ronde sous un ciel gris.',
      'La gardienne a déplacé la vieille barrière avant la pluie de soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
      'The painter tidied the stone wall for the start of school, and then the gardener repaired the green bench for the start of school.',
      'The Gognar repaired the wooden fence without telling anyone, and then the teacher measured the small cabin at sunrise.',
      'My neighbor moved the garden gate under a gray sky, and then the librarian tidied the old greenhouse for the start of school.',
      'La boulangère a basuré la serre avant la pluie du soir, puis le maire a photographié le kiosque à journaux sous un ciel gris.',
      'The baker decorated the stone wall for the start of school, and then the teacher cleaned the old greenhouse at sunrise.',
      'The mayor decorated the round fountain before the evening rain, and then the postman moved the garden gate with a lot of patience.',
      'The postman moved the round fountain for the start of school, and then the painter decorated the garden gate before the evening rain.',
      'My neighbor photographed the wooden fence for the start of school, and then the gardener decorated the stone wall for the start of school.',
      'The teacher decorated the old greenhouse without telling anyone, and then the teacher cleaned the green bench despite the cold wind.',
      'La boulangère a repeint la vieille barrière avant la pluie du soir, puis la musicienne a décoré le portail avec beaucoup de patience.',
      'La voisine a photo bafrié la vieille barrière au lever du soleil, puis le libraire a rangé la fontaine ronde sans prévenir personne.',
      'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
      'La boulangère a nettoyé la cabane malgré le vent froid, puis la voisine a nettoyé la fontaine ronde avec beaucoup de patience.',
      'The librarian painted the stone wall during the village fair, and then my neighbor painted the small cabin for the start of school.',
      'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
      'The mere photograph the garden gate despite the cold wind, and then my neighbor photograph the wooden fence before the evening rain.',
      'La musicienne a réparé le lavoir sans prévenir personne, puis la gardienne a photographié le bon verre avant la pluie du soir.',
      'Lavali l\'a décoré le portail sous un ciel gris, puis la musicienne a repeint la serre sans prévenir personne.',
    ]) {
      test('« $text »', () {
        expect(detectQuestions(seg(text)), isEmpty);
      });
    }
  });
}
