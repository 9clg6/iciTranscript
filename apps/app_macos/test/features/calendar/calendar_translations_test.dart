import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

// T5 : tous les textes de l'agenda, des suggestions de réunion et de la
// section Réglages viennent de fr.json. Valeurs françaises proposées à
// l'implémenteur (l'app vouvoie).
void main() {
  const Map<String, String> exact = <String, String>{
    'common.label.tomorrow': 'Demain',
    'home.upcoming.connect': "Connecter l'agenda",
    'home.upcoming.denied':
        "Oats n'a pas accès à votre agenda. Autorisez-le dans Réglages "
        'Système › Confidentialité et sécurité › Calendriers.',
    'home.upcoming.open_settings': 'Ouvrir Réglages Système',
    'home.upcoming.empty': "Aucune réunion aujourd'hui ni demain.",
    'home.upcoming.in_progress': 'En cours',
    'home.upcoming.start_note': 'Démarrer la note',
    'home.upcoming.error': "Impossible de lire l'agenda.",
    'meeting.suggestion.call_title': 'Appel détecté',
    'meeting.suggestion.start': 'Démarrer la note',
    'meeting.suggestion.dismiss': 'Ignorer',
    'settings.calendar.title': 'Agenda et réunions',
    'settings.calendar.connect': "Connecter l'agenda",
    'settings.calendar.disconnect': 'Déconnecter',
    'settings.calendar.denied':
        "Oats n'a pas accès à votre agenda. Autorisez-le dans Réglages "
        'Système › Confidentialité et sécurité › Calendriers.',
    'settings.calendar.open_settings': 'Ouvrir Réglages Système',
    'settings.calendar.calendars': 'Agendas inclus',
    'settings.calendar.detection': 'Détecter les réunions',
    'settings.calendar.auto_start':
        "Démarrer la note automatiquement pour les événements de l'agenda",
    'settings.calendar.mic_unsupported':
        'Détecter les appels demande macOS 14 ou plus récent. Ici, seuls '
        "les événements de l'agenda déclenchent une suggestion.",
    'settings.calendar.privacy':
        'Rien de votre agenda ni de vos appels ne quitte ce Mac.',
    'history.detail.calendar.unlink': 'Retirer le lien',
    'history.detail.calendar.change': "Changer d'événement",
    'history.detail.calendar.link': 'Lier à un événement',
    'history.detail.calendar.none': 'Aucun événement ce jour-là.',
  };

  exact.forEach((String key, String value) {
    test('$key = « $value »', () => expect(frValue(key), value));
  });

  test('home.upcoming.attendees garde ses formes « one » et « other »', () {
    expect(frValue('home.upcoming.attendees.one'), '{} participant');
    expect(frValue('home.upcoming.attendees.other'), '{} participants');
  });
}
