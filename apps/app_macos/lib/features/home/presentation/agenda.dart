import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Un jour de l'agenda et ses sessions, de la plus récente à la plus ancienne.
class AgendaDay {
  /// Crée un jour d'agenda.
  const AgendaDay({required this.day, required this.sessions});

  /// Minuit du jour (heure locale).
  final DateTime day;

  /// Sessions commencées ce jour-là.
  final List<SessionEntity> sessions;
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Groupe les sessions par jour de début, jours et sessions du plus récent
/// au plus ancien.
List<AgendaDay> groupSessionsByDay(List<SessionEntity> sessions) {
  final List<SessionEntity> sorted = <SessionEntity>[...sessions]
    ..sort(
      (SessionEntity a, SessionEntity b) => b.createdAt.compareTo(a.createdAt),
    );
  final List<AgendaDay> days = <AgendaDay>[];
  for (final SessionEntity s in sorted) {
    final DateTime day = _dayOf(s.createdAt);
    if (days.isEmpty || days.last.day != day) {
      days.add(AgendaDay(day: day, sessions: <SessionEntity>[]));
    }
    days.last.sessions.add(s);
  }
  return days;
}

/// En-tête de jour : « Aujourd'hui », « Hier », sinon « ven. 20 nov. »
/// (année ajoutée hors de l'année en cours).
String formatDayHeader(DateTime day, {required DateTime now}) {
  final DateTime d = _dayOf(day);
  final DateTime today = _dayOf(now);
  if (d == today) return LocaleKeys.common_label_today.tr();
  if (d == DateTime(today.year, today.month, today.day - 1)) {
    return LocaleKeys.common_label_yesterday.tr();
  }
  final String pattern = d.year == today.year ? 'E d MMM' : 'E d MMM y';
  return DateFormat(pattern, 'fr').format(d);
}

/// Heure de début « HH:mm ».
String formatStartTime(DateTime start) => DateFormat('HH:mm').format(start);

/// Durée lisible : « 52 min », « 1 h 07 », « < 1 min » ; null si inconnue.
// ponytail: unités en dur, l'app n'a que le français.
String? formatDuration(int? seconds) {
  if (seconds == null) return null;
  final int minutes = seconds ~/ 60;
  if (minutes == 0) return '< 1 min';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Retire accents et casse pour comparer des titres.
String _fold(String s) {
  const String from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const String to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final StringBuffer out = StringBuffer();
  for (final int rune in s.toLowerCase().runes) {
    final String c = String.fromCharCode(rune);
    final int i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

/// Sessions dont le titre contient [query], sans tenir compte de la casse
/// ni des accents ; requête vide = toutes.
List<SessionEntity> filterSessionsByTitle(
  List<SessionEntity> sessions,
  String query,
) {
  final String q = _fold(query.trim());
  if (q.isEmpty) return sessions;
  return sessions
      .where((SessionEntity s) => _fold(s.title).contains(q))
      .toList();
}
