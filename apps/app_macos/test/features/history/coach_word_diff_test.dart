import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_word_diff.dart';

/// Diff mot à mot d'une correction du coach anglais.
///
/// Besoin : dans chaque correction, seuls les MOTS fautifs de ce qui a été
/// dit sont barrés, seuls les mots nouveaux de la meilleure tournure sont
/// mis en avant ; les mots inchangés restent normaux.
///
/// API supposée (fonction pure, sans Flutter) :
/// `List<CoachDiffToken> coachWordDiff(String original, String corrected)`,
/// chaque jeton ayant `text` (un mot, sans espace) et `kind`
/// (`CoachDiffKind.same` / `.removed` / `.added`), dans l'ordre de lecture.
/// Les jetons `same` + `removed` redonnent les mots de [original] ; `same`
/// + `added`, ceux de [corrected]. Le diff est minimal (plus longue suite
/// commune) : un mot inséré ne décale pas les suivants.
///
/// Phrases inventées.
void main() {
  List<String> words(List<CoachDiffToken> tokens, CoachDiffKind kind) =>
      <String>[
        for (final CoachDiffToken t in tokens)
          if (t.kind == kind) t.text,
      ];

  List<String> originalSide(List<CoachDiffToken> tokens) => <String>[
    for (final CoachDiffToken t in tokens)
      if (t.kind != CoachDiffKind.added) t.text,
  ];

  List<String> correctedSide(List<CoachDiffToken> tokens) => <String>[
    for (final CoachDiffToken t in tokens)
      if (t.kind != CoachDiffKind.removed) t.text,
  ];

  test('un mot en trop : lui seul est retiré, rien n\'est ajouté', () {
    final List<CoachDiffToken> d = coachWordDiff('I am agree', 'I agree');

    expect(words(d, CoachDiffKind.removed), <String>['am']);
    expect(words(d, CoachDiffKind.added), isEmpty);
    expect(words(d, CoachDiffKind.same), <String>['I', 'agree']);
  });

  test('un mot remplacé : l\'ancien est retiré, le nouveau ajouté, le reste '
      'inchangé', () {
    final List<CoachDiffToken> d = coachWordDiff(
      'He have sent the deck',
      'He has sent the deck',
    );

    expect(words(d, CoachDiffKind.removed), <String>['have']);
    expect(words(d, CoachDiffKind.added), <String>['has']);
    expect(words(d, CoachDiffKind.same), <String>['He', 'sent', 'the', 'deck']);
  });

  test('un mot inséré au milieu ne fait pas passer les suivants pour '
      'changés', () {
    final List<CoachDiffToken> d = coachWordDiff(
      'I waiting for the client',
      'I am waiting for the client',
    );

    expect(words(d, CoachDiffKind.added), <String>['am']);
    expect(words(d, CoachDiffKind.removed), isEmpty);
    expect(words(d, CoachDiffKind.same), <String>[
      'I',
      'waiting',
      'for',
      'the',
      'client',
    ]);
  });

  test('plusieurs changements dans la phrase', () {
    final List<CoachDiffToken> d = coachWordDiff(
      'I am working here since two years',
      'I have been working here for two years',
    );

    expect(words(d, CoachDiffKind.removed), <String>['am', 'since']);
    expect(words(d, CoachDiffKind.added), <String>['have', 'been', 'for']);
  });

  test('chaque côté se relit dans l\'ordre de la phrase', () {
    const String original = 'We was ready for the demo yesterday';
    const String corrected = 'We were ready for the demo yesterday';
    final List<CoachDiffToken> d = coachWordDiff(original, corrected);

    expect(originalSide(d), original.split(' '));
    expect(correctedSide(d), corrected.split(' '));
  });

  test('phrases identiques : tout est inchangé', () {
    final List<CoachDiffToken> d = coachWordDiff(
      'Thanks for your help',
      'Thanks for your help',
    );

    expect(words(d, CoachDiffKind.same), <String>[
      'Thanks',
      'for',
      'your',
      'help',
    ]);
    expect(words(d, CoachDiffKind.removed), isEmpty);
    expect(words(d, CoachDiffKind.added), isEmpty);
  });

  test('espaces en trop ou en bord : aucun jeton vide ni avec espace', () {
    final List<CoachDiffToken> d = coachWordDiff('  I  am agree ', 'I agree  ');

    expect(
      d.where((CoachDiffToken t) => t.text.trim() != t.text || t.text.isEmpty),
      isEmpty,
    );
    expect(words(d, CoachDiffKind.removed), <String>['am']);
  });

  test('rien de dit (original vide) : tout le corrigé est ajouté', () {
    final List<CoachDiffToken> d = coachWordDiff('', 'Thank you');

    expect(words(d, CoachDiffKind.added), <String>['Thank', 'you']);
    expect(words(d, CoachDiffKind.removed), isEmpty);
  });
}
