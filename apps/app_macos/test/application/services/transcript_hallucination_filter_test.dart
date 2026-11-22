import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';

/// Besoin T1.5 : filtre des hallucinations sur le texte finalisé.
///
/// `filterFinalText(text, hadSpeechEnergy:, previousTexts:)` rend le texte à
/// garder (boucles de répétition réduites) ou null pour l'écarter.
/// - `hadSpeechEnergy` : l'énergie audio de la phrase atteignait le seuil de
///   parole.
/// - `previousTexts` : textes finalisés juste avant, même source, du plus
///   ancien au plus récent (gardés ou écartés).
///
/// Une hallucination connue n'est écartée que sur un audio sans parole, ou
/// si le même texte court revient au moins 3 fois de suite. Une réponse
/// courte légitime, avec de la parole et sans répétition, est gardée.
void main() {
  String? filter(
    String text, {
    bool hadSpeechEnergy = true,
    List<String> previousTexts = const <String>[],
  }) => TranscriptTextNormalizer.filterFinalText(
    text,
    hadSpeechEnergy: hadSpeechEnergy,
    previousTexts: previousTexts,
  );

  group('hallucinations connues sur un audio sans parole', () {
    for (final String hallucination in <String>[
      'Thank you.',
      'Thanks for watching!',
      "Sous-titres réalisés par la communauté d'Amara.org",
      "Merci d'avoir regardé cette vidéo",
      '♪',
      'you',
      'Okay.',
    ]) {
      test('écarte « $hallucination »', () {
        expect(filter(hallucination, hadSpeechEnergy: false), isNull);
      });
    }

    test('reconnaît une variante de casse, d espaces et de ponctuation', () {
      expect(filter('  thank you  ', hadSpeechEnergy: false), isNull);
      expect(filter('Thanks for watching.', hadSpeechEnergy: false), isNull);
      expect(filter('♪ ♪', hadSpeechEnergy: false), isNull);
    });
  });

  group('hallucinations connues avec de la parole', () {
    test('garde « Okay. » isolé', () {
      expect(filter('Okay.'), 'Okay.');
    });

    test('garde « Thank you. » isolé', () {
      expect(
        filter('Thank you.', previousTexts: <String>['Bonne journée.']),
        'Thank you.',
      );
    });

    test('garde « Okay. » répété deux fois seulement', () {
      expect(filter('Okay.', previousTexts: <String>['Okay.']), 'Okay.');
    });

    test('écarte la troisième occurrence consécutive', () {
      expect(
        filter(
          'Thank you.',
          previousTexts: <String>['Thank you.', 'Thank you.'],
        ),
        isNull,
      );
      expect(
        filter('you', previousTexts: <String>['Bonjour.', 'you', 'you']),
        isNull,
      );
    });

    test('ne compte pas une répétition interrompue', () {
      expect(
        filter(
          'Okay.',
          previousTexts: <String>['Okay.', 'On avance.', 'Okay.'],
        ),
        'Okay.',
      );
    });
  });

  group('réponses courtes légitimes', () {
    test('garde « Merci. » dit avec de la parole', () {
      expect(filter('Merci.', previousTexts: <String>['Merci.']), 'Merci.');
    });

    test('garde une phrase normale sur un audio faible', () {
      expect(
        filter('On se voit jeudi.', hadSpeechEnergy: false),
        'On se voit jeudi.',
      );
    });

    test('garde une phrase qui contient une formule connue', () {
      expect(
        filter('Thank you for the update on the budget.'),
        'Thank you for the update on the budget.',
      );
    });
  });

  group('boucles de répétition', () {
    test('réduit un mot répété en boucle à une occurrence', () {
      expect(filter('okay okay okay okay okay okay'), 'okay');
    });

    test('réduit la boucle au milieu d une phrase', () {
      expect(
        filter('Alors okay okay okay okay okay on commence.'),
        'Alors okay on commence.',
      );
    });

    test('réduit une phrase répétée trois fois ou plus', () {
      expect(
        filter('Je pense que oui. Je pense que oui. Je pense que oui.'),
        'Je pense que oui.',
      );
      expect(
        filter(
          'We can ship it. We can ship it. We can ship it. We can ship it.',
        ),
        'We can ship it.',
      );
    });

    test('garde une répétition naturelle de deux mots', () {
      expect(filter('Non non, pas du tout.'), 'Non non, pas du tout.');
    });

    test('réduit la boucle même sur un audio faible', () {
      expect(
        filter('on y va on y va on y va on y va', hadSpeechEnergy: false),
        'on y va',
      );
    });
  });

  test('un texte vide reste écarté', () {
    expect(filter('   '), isNull);
  });
}
