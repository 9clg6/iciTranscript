/// Lien d'une note vers une occurrence d'événement d'agenda.
class SessionCalendarLink {
  /// Crée le lien.
  const SessionCalendarLink({
    required this.eventId,
    required this.eventTitle,
    this.attendees = const <String>[],
  });

  /// Identifiant de l'occurrence.
  final String eventId;

  /// Titre de l'événement (devient le titre de la note).
  final String eventTitle;

  /// Noms des participants (jamais d'adresse e-mail).
  final List<String> attendees;
}
