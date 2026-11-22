import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';

// Tour 6, point 4b (sonde 4 : texte de type espagnol gardé tel quel, 5/5).
// Contrôle de langue simple et pur, pour les langues attendues des réunions
// (français et anglais par défaut, un seul endroit). Un texte d'au moins
// 6 mots dont les mots ne ressemblent à aucune langue attendue est signalé ;
// un texte plus court n'est jamais jugé. Noms propres, mélange FR/EN,
// nombres et noms de produits ne sont pas signalés.
//
// API supposée : `TranscriptTextNormalizer.expectedLanguages` (const
// {'fr', 'en'}), `TranscriptTextNormalizer.minWordsForLanguageCheck` (6),
// `TranscriptTextNormalizer.isUnexpectedLanguage(String text)`.
void main() {
  test('langues attendues et seuil, en un seul endroit', () {
    expect(TranscriptTextNormalizer.expectedLanguages, <String>{'fr', 'en'});
    expect(TranscriptTextNormalizer.minWordsForLanguageCheck, 6);
  });

  group('signalé : ni français ni anglais', () {
    for (final String text in <String>[
      'El equipo ha terminado el presupuesto para el próximo trimestre.',
      'Vamos a revisar los resultados de la reunión mañana por la tarde.',
      'No estoy seguro de que podamos entregar todo esta semana.',
      'Tenemos que hablar con el cliente sobre el contrato nuevo.',
      'Questo progetto deve essere finito entro la fine del mese.',
      'Non so se abbiamo abbastanza tempo per tutto questo lavoro.',
      'Dobbiamo parlare con il cliente del nuovo contratto domani.',
      'Wir müssen das Budget für das nächste Quartal noch einmal prüfen.',
      'Ich glaube nicht, dass wir das bis Freitag schaffen werden.',
      'Nós precisamos terminar o relatório antes da próxima semana.',
      'Eu acho que isso não vai funcionar com o nosso cliente.',
      'We moeten het budget voor het volgende kwartaal nog bekijken.',
      'Ik denk niet dat we dat voor vrijdag kunnen halen.',
      'Musimy jeszcze raz sprawdzić budżet na następny kwartał.',
      'Det er ikke sikkert at vi rekker alt denne uken.',
      'Aap kaise hain aur aaj ka kaam kya hai yaar.',
    ]) {
      test(text, () {
        expect(TranscriptTextNormalizer.isUnexpectedLanguage(text), isTrue);
      });
    }
  });

  group('jamais signalé', () {
    for (final String text in <String>[
      'Bonjour à tous, on commence la réunion maintenant.',
      'We will ship the new release next week.',
      'Merci beaucoup pour votre présentation, c était très clair.',
      'Donc voilà, c est un peu compliqué pour le moment.',
      'Okay, let us move on to the next point please.',
      // Noms propres d'ailleurs dans une phrase attendue.
      'Le budget du troisième trimestre est validé par Marc.',
      'On a parlé avec Gonzalez et Rodriguez de Madrid hier.',
      'The meeting with Müller and Schäfer from Berlin went well.',
      // Mélange français / anglais.
      'Je pense que le sprint review est prévu jeudi.',
      'Can you send me le compte rendu de la réunion ?',
      'So basically the API returns a JSON payload with the user id.',
      // Nombres et noms de produits.
      'Il faut mettre à jour Kubernetes et PostgreSQL avant vendredi.',
      'We deployed version 2.4.1 on 12 servers in 3 regions.',
      'Le chiffre d affaires est de 1 250 000 euros en 2025.',
      'iPhone, MacBook, AirPods, Vision Pro et Apple Watch.',
      // Trop courts pour être jugés, même dans une autre langue.
      'Gracias amigo.',
      'Vamos !',
      'Ja, genau, danke schön.',
    ]) {
      test(text, () {
        expect(TranscriptTextNormalizer.isUnexpectedLanguage(text), isFalse);
      });
    }
  });
}
