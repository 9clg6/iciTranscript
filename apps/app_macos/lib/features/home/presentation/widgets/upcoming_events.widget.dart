import 'dart:async';

import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/calendar/calendar_rules.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/start_note.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Bloc « À venir » de l'accueil : réunions d'aujourd'hui et de demain lues
/// dans l'agenda, une fois connecté.
class UpcomingEventsBlock extends ConsumerStatefulWidget {
  /// Crée le bloc.
  const UpcomingEventsBlock({super.key});

  @override
  ConsumerState<UpcomingEventsBlock> createState() =>
      _UpcomingEventsBlockState();
}

class _UpcomingEventsBlockState extends ConsumerState<UpcomingEventsBlock> {
  // « En cours » et les événements finis suivent l'horloge.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final AsyncValue<CalendarFeed> feed = ref.watch(
      calendarFeedControllerProvider,
    );
    final CalendarFeedController calendar = ref.read(
      calendarFeedControllerProvider.notifier,
    );
    final DateTime now = ref.watch(nowProvider)();
    final CalendarFeed? value = feed.value;

    final List<Widget> body;
    if (feed.hasError && !feed.isLoading) {
      body = <Widget>[
        OatsNotice(
          icon: Icons.error_outline,
          danger: true,
          message: LocaleKeys.home_upcoming_error.tr(),
          actions: <Widget>[
            OatsButton(
              label: LocaleKeys.common_action_retry.tr(),
              onPressed: calendar.retry,
            ),
          ],
        ),
      ];
    } else {
      body = switch (value) {
        null => const <Widget>[],
        CalendarNotConnected() => <Widget>[
          OatsNotice(
            icon: Icons.calendar_today_outlined,
            message: LocaleKeys.home_upcoming_no_calendar.tr(),
            actions: <Widget>[
              OatsButton(
                icon: Icons.link,
                label: LocaleKeys.home_upcoming_connect.tr(),
                onPressed: calendar.connect,
              ),
            ],
          ),
        ],
        CalendarDenied() => <Widget>[
          OatsNotice(
            icon: Icons.lock_outline,
            message: LocaleKeys.home_upcoming_denied.tr(),
            actions: <Widget>[
              OatsButton(
                label: LocaleKeys.home_upcoming_open_settings.tr(),
                onPressed: calendar.openPrivacySettings,
              ),
            ],
          ),
        ],
        CalendarEvents(:final List<CalendarEvent> events) => _events(
          context,
          upcomingEvents(events, now),
          now,
        ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(LocaleKeys.home_upcoming_title.tr(), style: o.title),
        ),
        const SizedBox(height: OatsSpace.md),
        ...body,
      ],
    );
  }

  List<Widget> _events(
    BuildContext context,
    List<CalendarEvent> events,
    DateTime now,
  ) {
    if (events.isEmpty) {
      return <Widget>[
        Text(LocaleKeys.home_upcoming_empty.tr(), style: context.oats.small),
      ];
    }
    return <Widget>[
      for (final CalendarEvent e in events) ...<Widget>[
        _EventCard(
          event: e,
          now: now,
          onStart: () => startOrShowNote(ref.read),
        ),
        const SizedBox(height: OatsSpace.sm),
      ],
    ];
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.now,
    required this.onStart,
  });

  final CalendarEvent event;
  final DateTime now;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final bool inProgress = isInProgress(event, now);
    final bool tomorrow = startOfDay(event.start).isAfter(startOfDay(now));
    final String when = <String>[
      if (tomorrow) LocaleKeys.common_label_tomorrow.tr(),
      '${formatStartTime(event.start)}–${formatStartTime(event.end)}',
      if (event.attendeeCount > 0)
        LocaleKeys.home_upcoming_attendees.plural(event.attendeeCount),
      if (event.calendarTitle.isNotEmpty) event.calendarTitle,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.lg,
        vertical: OatsSpace.md,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: o.line),
        borderRadius: BorderRadius.circular(OatsRadius.lg),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: o.bodyStrong,
                ),
                Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: o.meta,
                ),
              ],
            ),
          ),
          if (inProgress) ...<Widget>[
            const SizedBox(width: OatsSpace.md),
            OatsChip(label: LocaleKeys.home_upcoming_in_progress.tr()),
            const SizedBox(width: OatsSpace.sm),
            _StartNoteButton(onStart: onStart),
          ],
        ],
      ),
    );
  }
}

/// « Démarrer la note » ; pendant un enregistrement, ramène au direct.
class _StartNoteButton extends ConsumerWidget {
  const _StartNoteButton({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool recording = ref.watch(
      liveTranscriptionViewModelProvider.select(
        (LiveTranscriptionState s) => s.isRecording || s.isPaused,
      ),
    );
    return OatsButton(
      icon: recording ? Icons.arrow_forward : Icons.mic_none_outlined,
      label: LocaleKeys.home_upcoming_start_note.tr(),
      onPressed: onStart,
    );
  }
}
