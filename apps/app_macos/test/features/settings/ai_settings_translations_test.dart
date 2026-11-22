import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

/// Textes de la section IA des Réglages (besoin 9) : tous dans fr.json.
///
/// Indispensable : une clé absente fait rendre la clé elle-même par `.tr()`,
/// des deux côtés (code et test), et les tests d'écran passeraient à tort.
void main() {
  group('valeurs imposées par le besoin', () {
    const Map<String, String> exact = <String, String>{
      'settings.ai.cloud_allowed': "Autoriser l'envoi à un service en ligne",
      'settings.ai.provider.anthropic': 'Claude',
      'settings.ai.provider.openai': 'OpenAI',
      'settings.ai.provider.gemini': 'Gemini',
      'settings.ai.provider.ollama': 'Local (Ollama)',
      // « •••• » suivi des 4 derniers caractères de la clé.
      'settings.ai.key_saved': '•••• {}',
      'settings.ai.replace': 'Remplacer',
      'settings.ai.remove': 'Supprimer',
      // Résumer et Coach envoient la transcription de n'importe quelle note
      // demandée, pas seulement celle de la réunion en cours.
      'settings.ai.privacy_notice':
          "Quand l'envoi est autorisé, le texte des notes que vous faites "
          "résumer ou analyser, celui de la réunion en cours et des extraits "
          "de vos documents partent chez le fournisseur choisi. L'audio reste "
          'sur votre Mac.',
    };
    exact.forEach((String key, String value) {
      test('$key = « $value »', () => expect(frValue(key), value));
    });

    // Le besoin les cite en minuscules ; la majuscule initiale est libre.
    const Map<String, String> results = <String, String>{
      'settings.ai.test_invalid_key': 'clé invalide',
      'settings.ai.test_rate_limited': 'limite atteinte',
      'settings.ai.test_unreachable': 'injoignable',
    };
    results.forEach((String key, String value) {
      test('$key = « $value »', () {
        expect((frValue(key) as String?)?.toLowerCase(), value);
      });
    });
  });

  group('clés présentes et non vides', () {
    const List<String> keys = <String>[
      'settings.ai.title',
      'settings.ai.api_key_label',
      'settings.ai.save',
      'settings.ai.test',
      'settings.ai.testing',
      'settings.ai.test_ok',
      'settings.ai.test_failed',
      'settings.ai.key_error',
      'settings.ai.active_provider',
      'settings.ai.model_label',
      'settings.ai.privacy_notice',
    ];
    for (final String key in keys) {
      test(key, () {
        final Object? v = frValue(key);
        expect(v, isA<String>(), reason: key);
        expect((v! as String).trim(), isNotEmpty, reason: key);
      });
    }
  });

  test('la phrase de confidentialité dit ce qui part et que l\'audio reste '
      'sur le Mac', () {
    final String notice = (frValue('settings.ai.privacy_notice') as String?)
            ?.toLowerCase() ??
        '';
    // Nouvelle phrase imposée (revue PR #17) : « le texte des notes … celui
    // de la réunion en cours » remplace « la transcription ».
    expect(notice, contains('notes'));
    expect(notice, contains('réunion en cours'));
    expect(notice, contains('document'));
    expect(notice, contains('audio'));
    expect(notice, contains('mac'));
  });
}
