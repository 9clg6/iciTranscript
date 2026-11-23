import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

/// Textes du coach anglais (après l'appel, en direct, page « Coach anglais »)
/// : présents dans fr.json, non vides ; les pluriels ont leurs deux formes ;
/// l'état d'échec du direct dit « indisponible » (mot de Clément).
void main() {
  const List<String> keys = <String>[
    // Note : une partie de la réunion n'a pas été analysée.
    'coach.unanalyzed',
    // Direct : interrupteur, description, raison d'indisponibilité, état.
    'coach.live.option',
    'coach.live.description',
    'coach.live.unavailable',
    'coach.live.state_unavailable',
    // Page « Coach anglais » : erreurs récurrentes.
    'coach.recurring.title',
    // Déjà là, réutilisés.
    'coach.empty',
    'history.detail.coach_perfect',
    'common.action.retry',
    'common.error.generic',
  ];
  for (final String key in keys) {
    test('$key est présent et non vide', () {
      final Object? value = frValue(key);
      expect(value, isA<String>(), reason: key);
      expect((value! as String).trim(), isNotEmpty, reason: key);
    });
  }

  for (final String key in <String>[
    'coach.corrections',
    'coach.recurring.notes',
  ]) {
    test('$key a ses formes « one » et « other », avec le nombre', () {
      final Object? value = frValue(key);
      expect(value, isA<Map<String, dynamic>>(), reason: key);
      final Map<String, dynamic> forms = value! as Map<String, dynamic>;
      expect(forms['one'], contains('{}'));
      expect(forms['other'], contains('{}'));
    });
  }

  test('l\'état d\'échec du coach en direct dit « indisponible »', () {
    expect(
      (frValue('coach.live.state_unavailable') as String?)?.toLowerCase(),
      contains('indisponible'),
    );
  });

  test('la raison d\'indisponibilité parle du service en ligne', () {
    expect(
      (frValue('coach.live.unavailable') as String?)?.toLowerCase(),
      contains('en ligne'),
    );
  });
}
