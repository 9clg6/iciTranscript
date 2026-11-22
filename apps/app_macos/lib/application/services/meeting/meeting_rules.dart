import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/calendar/calendar_rules.dart';

/// Un événement est suggéré quand il commence dans ce délai.
const Duration kEventSuggestLead = Duration(minutes: 1);

/// Une app d'appel doit tenir le micro au moins ce temps.
const Duration kMicHoldThreshold = Duration(seconds: 3);

/// « Ignorer » met toute suggestion en sourdine ce temps.
const Duration kDismissSnooze = Duration(minutes: 10);

/// Participants minimum pour qu'un événement soit une réunion.
const int kMinAttendeesForSuggestion = 2;

/// Bundle id d'Oats (identifiant historique conservé).
const String kOwnBundleId = 'fr.yellowstone-apps.ici-transcript';

/// Apps d'appel et navigateurs connus : bundle id → nom affiché. Leurs
/// processus auxiliaires (`<id>.helper…`) comptent pour elles.
const Map<String, String> kCallApps = <String, String>{
  'us.zoom.xos': 'Zoom',
  'com.microsoft.teams2': 'Microsoft Teams',
  'com.microsoft.teams': 'Microsoft Teams',
  'com.tinyspeck.slackmacgap': 'Slack',
  'com.apple.FaceTime': 'FaceTime',
  'net.whatsapp.WhatsApp': 'WhatsApp',
  'Cisco-Systems.Spark': 'Webex',
  'com.hnc.Discord': 'Discord',
  'com.google.Chrome': 'Google Chrome',
  'com.apple.Safari': 'Safari',
  'company.thebrowser.Browser': 'Arc',
  'org.mozilla.firefox': 'Firefox',
  'com.microsoft.edgemac': 'Microsoft Edge',
  'com.brave.Browser': 'Brave',
  // Processus auxiliaires qui capturent pour une app sans porter son id.
  // Safari (et toute vue WebKit) capture le micro dans le processus GPU.
  'com.apple.WebKit.GPU': 'Safari',
  // ponytail: id du processus enfant de Firefox supposé, à confirmer par un
  // vrai appel Meet dans Firefox.
  'org.mozilla.plugincontainer': 'Firefox',
};

/// Nom de l'app d'appel de [bundleId] (id exact ou processus auxiliaire
/// `<id connu>.…`, sans tenir compte de la casse) ; null si inconnue.
String? callAppName(String bundleId) {
  final String id = bundleId.toLowerCase();
  for (final MapEntry<String, String> app in kCallApps.entries) {
    final String known = app.key.toLowerCase();
    if (id == known || id.startsWith('$known.')) return app.value;
  }
  return null;
}

/// Origine d'une suggestion.
enum MeetingSource {
  /// Événement d'agenda.
  calendar,

  /// App d'appel qui tient le micro.
  call,
}

/// Proposition de démarrer une note.
class MeetingSuggestion {
  /// Crée la suggestion.
  const MeetingSuggestion({
    required this.source,
    required this.key,
    this.event,
    this.appName,
    this.bundleId,
  });

  /// Origine.
  final MeetingSource source;

  /// Clé opaque : une même clé n'est jamais montrée deux fois.
  final String key;

  /// Événement (source agenda).
  final CalendarEvent? event;

  /// Nom de l'app d'appel (source appel).
  final String? appName;

  /// Bundle id du processus qui tient le micro (source appel).
  final String? bundleId;
}

/// Suggestion à montrer maintenant, ou null. L'agenda passe avant le micro.
MeetingSuggestion? meetingSuggestion({
  required DateTime now,
  required List<CalendarEvent> events,
  required Map<String, DateTime> micHolders,
  required bool ownCaptureActive,
  required bool detectionEnabled,
  Set<String> eventIdsWithNote = const <String>{},
  Set<String> alreadySuggested = const <String>{},
  DateTime? dismissedAt,
}) {
  if (!detectionEnabled || ownCaptureActive) return null;
  if (dismissedAt != null && now.difference(dismissedAt) < kDismissSnooze) {
    return null;
  }
  final List<CalendarEvent> due =
      events
          .where(
            (CalendarEvent e) =>
                isMeeting(e) &&
                e.attendeeCount >= kMinAttendeesForSuggestion &&
                e.end.isAfter(now) &&
                !e.start.isAfter(now.add(kEventSuggestLead)) &&
                !eventIdsWithNote.contains(e.id) &&
                !alreadySuggested.contains(_eventKey(e.id)),
          )
          .toList()
        ..sort(
          (CalendarEvent a, CalendarEvent b) => b.start.compareTo(a.start),
        );
  if (due.isNotEmpty) {
    // Le plus récent : en cas de réunions à la suite, celle qui commence.
    return MeetingSuggestion(
      source: MeetingSource.calendar,
      key: _eventKey(due.first.id),
      event: due.first,
    );
  }
  for (final MapEntry<String, DateTime> holder in micHolders.entries) {
    final String? app = holder.key == kOwnBundleId
        ? null
        : callAppName(holder.key);
    final String key = _callKey(holder.key, holder.value);
    if (app != null &&
        now.difference(holder.value) >= kMicHoldThreshold &&
        !alreadySuggested.contains(key)) {
      return MeetingSuggestion(
        source: MeetingSource.call,
        key: key,
        appName: app,
        bundleId: holder.key,
      );
    }
  }
  return null;
}

/// La suggestion [s] tient encore : événement toujours là et pas fini, ou
/// app toujours sur le micro.
bool suggestionStillValid(
  MeetingSuggestion s, {
  required DateTime now,
  required List<CalendarEvent> events,
  required Map<String, DateTime> micHolders,
}) => switch (s.source) {
  MeetingSource.calendar => events.any(
    (CalendarEvent e) => e.id == s.event?.id && e.end.isAfter(now),
  ),
  MeetingSource.call => micHolders.containsKey(s.bundleId),
};

String _eventKey(String id) => 'event:$id';

// Une nouvelle prise de micro (autre heure de début) = nouvelle clé.
String _callKey(String bundleId, DateTime since) =>
    'call:$bundleId:${since.millisecondsSinceEpoch}';
