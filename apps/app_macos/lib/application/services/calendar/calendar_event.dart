/// Autorisation de lire l'agenda macOS.
///
/// Seul l'accès complet permet de lire ; écriture seule, restreint ou refusé
/// valent [denied].
enum CalendarAccess {
  /// L'utilisateur n'a pas encore répondu à l'invite système.
  notDetermined,

  /// Accès complet.
  granted,

  /// Refusé (ou insuffisant pour lire).
  denied,
}

/// Un agenda de l'utilisateur.
class CalendarInfo {
  /// Crée l'agenda.
  const CalendarInfo({required this.id, required this.title});

  /// Identifiant EventKit.
  final String id;

  /// Nom affiché.
  final String title;
}

/// Une occurrence d'événement d'agenda.
class CalendarEvent {
  /// Crée l'événement.
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.declined = false,
    this.calendarId = '',
    this.calendarTitle = '',
    this.attendeeNames = const <String>[],
    this.attendeeCount = 0,
  });

  /// Identifiant unique par occurrence (événements récurrents compris).
  final String id;

  /// Titre.
  final String title;

  /// Début.
  final DateTime start;

  /// Fin.
  final DateTime end;

  /// Journée entière.
  final bool allDay;

  /// L'utilisateur a refusé l'invitation.
  final bool declined;

  /// Identifiant de l'agenda.
  final String calendarId;

  /// Nom de l'agenda.
  final String calendarTitle;

  /// Noms des participants (jamais d'adresse e-mail).
  final List<String> attendeeNames;

  /// Nombre de participants, adresses sans nom comprises.
  final int attendeeCount;
}
