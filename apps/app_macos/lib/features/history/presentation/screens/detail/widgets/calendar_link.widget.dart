import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/calendar/calendar_rules.dart';
import 'package:ici_transcript/core/providers/platform/calendar_channel.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_prefs.provider.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Largeur du choix d'événement.
const double kEventPickerWidth = 420;

/// Lien de la note à l'agenda : participants en puces, puis « Changer
/// d'événement » / « Retirer le lien », ou « Lier à un événement ». Changer
/// ou lier demande un agenda connecté et autorisé ; retirer, jamais.
class CalendarLinkBlock extends ConsumerWidget {
  /// Crée le bloc.
  const CalendarLinkBlock({
    required this.session,
    required this.onLink,
    super.key,
  });

  /// Note affichée.
  final SessionEntity session;

  /// Pose (événement) ou retire (null) le lien.
  final Future<void> Function(CalendarEvent? event) onLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool linked = session.calendarEventId != null;
    final bool canPick =
        ref.watch(calendarFeedControllerProvider).value is CalendarEvents;
    if (!linked && !canPick) return const SizedBox.shrink();
    return Wrap(
      spacing: OatsSpace.xs + 2,
      runSpacing: OatsSpace.xs + 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final String name in session.attendees)
          OatsChip(icon: Icons.person_outline, label: name),
        if (canPick)
          OatsButton(
            icon: Icons.event_outlined,
            label: linked
                ? LocaleKeys.history_detail_calendar_change.tr()
                : LocaleKeys.history_detail_calendar_link.tr(),
            onPressed: () => _pick(context, ref),
          ),
        if (linked)
          OatsButton(
            icon: Icons.link_off,
            label: LocaleKeys.history_detail_calendar_unlink.tr(),
            onPressed: () => onLink(null),
          ),
      ],
    );
  }

  /// Choix parmi les réunions du jour de la note.
  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final DateTime day = startOfDay(session.createdAt);
    final CalendarPrefs? prefs = ref
        .read(calendarPrefsControllerProvider)
        .value;
    List<CalendarEvent>? events;
    try {
      events =
          (await ref
                  .read(calendarChannelProvider)
                  .events(
                    from: day,
                    to: DateTime(day.year, day.month, day.day + 1),
                    calendarIds: prefs?.calendarIds,
                  ))
              .where(isMeeting)
              .toList()
            ..sort(
              (CalendarEvent a, CalendarEvent b) => a.start.compareTo(b.start),
            );
    } on Object {
      events = null;
    }
    if (!context.mounted) return;
    final Oats o = context.oats;
    final CalendarEvent? chosen = await showDialog<CalendarEvent>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          session.calendarEventId != null
              ? LocaleKeys.history_detail_calendar_change.tr()
              : LocaleKeys.history_detail_calendar_link.tr(),
        ),
        content: SizedBox(
          width: kEventPickerWidth,
          child: switch (events) {
            null => Text(LocaleKeys.home_upcoming_error.tr(), style: o.small),
            [] => Text(
              LocaleKeys.history_detail_calendar_none.tr(),
              style: o.small,
            ),
            final List<CalendarEvent> list => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final CalendarEvent e in list)
                    OatsListRow(
                      title: e.title,
                      trailing:
                          '${formatStartTime(e.start)}–${formatStartTime(e.end)}',
                      onTap: () => Navigator.of(dialogContext).pop(e),
                    ),
                ],
              ),
            ),
          },
        ),
        actions: <Widget>[
          OatsButton(
            label: LocaleKeys.common_action_cancel.tr(),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (chosen != null) await onLink(chosen);
  }
}
