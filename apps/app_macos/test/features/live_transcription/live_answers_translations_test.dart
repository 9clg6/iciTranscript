import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

/// Textes des questions/réponses en direct (T4) : tous dans fr.json, valeurs
/// françaises fixées ici pour l'implémenteur. Réutilisés tels quels :
/// `common.action.retry` (« Réessayer »), `llm.configure_model`,
/// `transcription.live.speaker_me`, `transcription.live.speaker_n`,
/// `history.detail.speaker_me`, `history.detail.speaker`.
void main() {
  const Map<String, String> exact = <String, String>{
    'live_answers.title': 'Questions',
    'live_answers.empty':
        'Les questions des autres participants apparaîtront ici.',
    'live_answers.answer_latest': 'Répondre',
    'live_answers.answer_this': 'Répondre à cette phrase',
    'live_answers.answer': 'Proposer une réponse',
    'live_answers.answering': 'Réponse en cours…',
    'live_answers.copy': 'Copier la réponse',
    'live_answers.copied': 'Réponse copiée',
    'live_answers.dismiss': 'Ignorer',
    'live_answers.declined': 'Pas de réponse utile à proposer.',
    'live_answers.truncated': 'Réponse incomplète',
    'live_answers.error.invalid_key':
        'Clé API refusée : vérifiez-la dans Réglages.',
    'live_answers.error.rate_limited':
        'Trop de demandes chez le fournisseur : réessayez dans un instant.',
    'live_answers.error.unreachable':
        'Modèle injoignable : vérifiez la connexion, puis réessayez.',
    'live_answers.error.malformed': 'Réponse illisible du modèle : réessayez.',
    'live_answers.error.other': 'La réponse a échoué : réessayez.',
    'history.detail.questions': 'Questions posées',
    'history.detail.no_answer': 'Sans réponse',
  };

  exact.forEach((String key, String value) {
    test('$key = « $value »', () => expect(frValue(key), value));
  });

  test('les textes réutilisés existent toujours', () {
    for (final String key in <String>[
      'common.action.retry',
      'llm.configure_model',
      'transcription.live.speaker_me',
      'transcription.live.speaker_n',
      'history.detail.speaker_me',
      'history.detail.speaker',
    ]) {
      expect(frValue(key), isA<String>(), reason: key);
    }
  });
}
