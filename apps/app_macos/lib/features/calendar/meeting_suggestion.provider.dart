import 'dart:async';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/core/providers/platform/meeting_detection_channel.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
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
  final Log _log = Log.named('MeetingSuggestion');

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
    final CalendarEvent? event = state?.event;
    state = null;
    await startOrShowNote(ref.read, event: event);
  }

  /// « Ignorer » : plus rien pendant [kDismissSnooze].
  void dismiss() {
    _dismissedAt = ref.read(nowProvider)();
    state = null;
  }

  void _onMicUsers(Set<String> bundleIds) {
    final DateTime now = ref.read(nowProvider)();
    // Ids seulement (jamais de titre ni de nom) : sert à compléter kCallApps
    // quand un vrai appel ne déclenche rien.
    for (final String id in bundleIds) {
      if (!_holders.containsKey(id) && callAppName(id) == null) {
        _log.info('Micro tenu par une app non reconnue : $id');
      }
    }
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
    final bool recording = live.isRecording || live.isPaused;
    // Oats enregistre ou dicte : son propre micro n'est jamais un appel, et
    // rien de nouveau n'apparaît ni ne démarre seul.
    final bool ownCapture = recording || ref.read(dictationActiveProvider);

    final MeetingSuggestion? current = state;
    if (current != null) {
      // Une invite déjà affichée reste pendant une dictée (l'utilisateur
      // ne l'a pas ignorée) ; un enregistrement la retire.
      if (recording ||
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
      unawaited(startOrShowNote(ref.read, event: next.event));
      return;
    }
    state = next;
  }
}
