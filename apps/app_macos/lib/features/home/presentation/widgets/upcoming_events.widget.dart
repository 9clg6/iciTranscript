import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Réunion à venir lue dans l'agenda.
class UpcomingEvent {
  /// Crée un événement.
  const UpcomingEvent({
    required this.title,
    required this.start,
    required this.attendeesCount,
  });

  /// Titre de l'événement.
  final String title;

  /// Début de l'événement.
  final DateTime start;

  /// Nombre de participants.
  final int attendeesCount;
}

/// Bloc « À venir » de l'accueil. Sans agenda connecté : état vide explicite.
class UpcomingEventsBlock extends StatelessWidget {
  /// Crée le bloc.
  const UpcomingEventsBlock({
    required this.events,
    this.calendarConnected = false,
    super.key,
  });

  /// Événements à afficher, du plus proche au plus lointain.
  final List<UpcomingEvent> events;

  /// Un agenda est connecté (sinon l'état vide l'explique).
  final bool calendarConnected;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(LocaleKeys.home_upcoming_title.tr(), style: o.title),
        ),
        const SizedBox(height: OatsSpace.md),
        if (!calendarConnected)
          OatsNotice(
            icon: Icons.calendar_today_outlined,
            message: LocaleKeys.home_upcoming_no_calendar.tr(),
          )
        else
          for (final UpcomingEvent e in events) ...<Widget>[
            _EventCard(event: e),
            const SizedBox(height: OatsSpace.sm),
          ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final UpcomingEvent event;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String when = <String>[
      DateFormat('E d MMM', 'fr').format(event.start),
      formatStartTime(event.start),
      LocaleKeys.home_upcoming_attendees.plural(event.attendeesCount),
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
          SizedBox(
            width: 36,
            child: Text('${event.start.day}', style: o.title),
          ),
          const SizedBox(width: OatsSpace.md),
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
                Text(when, style: o.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
