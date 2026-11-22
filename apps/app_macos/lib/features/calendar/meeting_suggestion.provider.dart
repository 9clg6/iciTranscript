import 'dart:async';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/platform/meeting_detection_channel.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_prefs.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/start_note.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'meeting_suggestion.provider.g.dart';

/// Lance la surveillance du micro une fois ; false sous macOS 14 (seuls les
/// événements de l'agenda déclenchent alors une suggestion).
// ponytail: la surveillance tourne toute la vie de l'app, détection coupée
// ou non (quelques écouteurs Core Audio) ; les instantanés sont alors
// ignorés.
@Riverpod(keepAlive: true)
Future<bool> meetingDetectionSupported(Ref ref) =>
    ref.read(meetingDetectionChannelProvider).start();

/// Suggestion de démarrer une note affichée par le shell, ou null.
@Riverpod(keepAlive: true)
class MeetingSuggestionController extends _$MeetingSuggestionController {
  // Bundle id → depuis quand il tient le micro (horloge d'Oats).
  final Map<String, DateTime> _holders = <String, DateTime>{};
  final Set<String> _shown = <String>{};
  DateTime? _dismissedAt;

  @override
  MeetingSuggestion? build() {
    unawaited(ref.read(meetingDetectionSupportedProvider.future));
    final StreamSubscription<Set<String>> sub = ref
        .read(meetingDetectionChannelProvider)
        .micUsers
        .listen(_onMicUsers);
    // ponytail: une évaluation par seconde suffit (seuils de 3 s et 1 min).
    final Timer tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _evaluate(),
    );
    ref.onDispose(() {
      unawaited(sub.cancel());
      tick.cancel();
    });
    return null;
  }

  /// « Démarrer la note ».
  Future<void> start() async {
    state = null;
    await startOrShowNote(ref.read);
  }

  /// « Ignorer » : plus rien pendant [kDismissSnooze].
  void dismiss() {
    _dismissedAt = ref.read(nowProvider)();
    state = null;
  }

  void _onMicUsers(Set<String> bundleIds) {
    final DateTime now = ref.read(nowProvider)();
    _holders.removeWhere((String id, _) => !bundleIds.contains(id));
    for (final String id in bundleIds) {
      _holders.putIfAbsent(id, () => now);
    }
    _evaluate();
  }

  void _evaluate() {
    final CalendarPrefs? prefs = ref
        .read(calendarPrefsControllerProvider)
        .value;
    if (prefs == null) return;
    final DateTime now = ref.read(nowProvider)();
    final CalendarFeed? feed = ref.read(calendarFeedControllerProvider).value;
    final List<CalendarEvent> events = feed is CalendarEvents
        ? feed.events
        : const <CalendarEvent>[];
    final LiveTranscriptionState live = ref.read(
      liveTranscriptionViewModelProvider,
    );
    final bool ownCapture = live.isRecording || live.isPaused;

    final MeetingSuggestion? current = state;
    if (current != null) {
      if (ownCapture ||
          !prefs.detectionEnabled ||
          !suggestionStillValid(
            current,
            now: now,
            events: events,
            micHolders: _holders,
          )) {
        state = null;
      }
      return;
    }

    final MeetingSuggestion? next = meetingSuggestion(
      now: now,
      events: events,
      micHolders: _holders,
      ownCaptureActive: ownCapture,
      detectionEnabled: prefs.detectionEnabled,
      eventIdsWithNote: <String>{
        for (final SessionEntity s
            in ref.read(sessionListViewModelProvider).sessions)
          ?s.calendarEventId,
      },
      alreadySuggested: _shown,
      dismissedAt: _dismissedAt,
    );
    if (next == null) return;
    _shown.add(next.key);
    if (next.source == MeetingSource.calendar && prefs.autoStart) {
      unawaited(startOrShowNote(ref.read));
      return;
    }
    state = next;
  }
}
