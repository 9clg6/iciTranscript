import 'package:ici_transcript/application/services/calendar/calendar_event.dart';

/// Une note qui démarre se lie à un événement qui commence au plus tard
/// dans ce délai.
const Duration kLinkLeadTime = Duration(minutes: 5);

/// Retard de démarrage toléré : un événement commencé depuis ce délai reste
/// lié. Un événement en cours plus ancien l'est aussi, mais un événement
/// plus proche du démarrage passe devant (classement par écart au début).
const Duration kLinkLateStart = Duration(minutes: 15);

/// Ni journée entière ni invitation refusée.
bool isMeeting(CalendarEvent e) => !e.allDay && !e.declined;

/// [e] a commencé et n'est pas fini à [now].
bool isInProgress(CalendarEvent e, DateTime now) =>
    !e.start.isAfter(now) && e.end.isAfter(now);

/// Événements d'aujourd'hui et de demain pas encore finis, sans journée
/// entière ni refusés, triés par début.
List<CalendarEvent> upcomingEvents(List<CalendarEvent> events, DateTime now) {
  final DateTime limit = DateTime(now.year, now.month, now.day + 2);
  return events
      .where(
        (CalendarEvent e) =>
            isMeeting(e) && e.end.isAfter(now) && e.start.isBefore(limit),
      )
      .toList()
    ..sort((CalendarEvent a, CalendarEvent b) => a.start.compareTo(b.start));
}

/// Événement auquel lier une note démarrée à [startedAt] : en cours ou
/// commençant dans [kLinkLeadTime], le plus proche du démarrage ; null sinon.
CalendarEvent? eventToLink(List<CalendarEvent> events, DateTime startedAt) {
  final DateTime latestStart = startedAt.add(kLinkLeadTime);
  CalendarEvent? best;
  Duration? bestGap;
  for (final CalendarEvent e in events) {
    if (!isMeeting(e) ||
        !e.end.isAfter(startedAt) ||
        e.start.isAfter(latestStart)) {
      continue;
    }
    final Duration gap = e.start.difference(startedAt).abs();
    if (bestGap == null || gap < bestGap) {
      best = e;
      bestGap = gap;
    }
  }
  return best;
}
