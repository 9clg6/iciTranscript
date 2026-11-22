import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Largeur de l'invite de réunion.
const double kMeetingSuggestionWidth = 340;

/// Invite non bloquante « Démarrer la note / Ignorer », en bas à droite du
/// contenu ; rien quand il n'y a pas de suggestion.
class MeetingSuggestionPrompt extends ConsumerWidget {
  /// Crée l'invite.
  const MeetingSuggestionPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MeetingSuggestion? s = ref.watch(meetingSuggestionControllerProvider);
    if (s == null) return const SizedBox.shrink();
    final MeetingSuggestionController controller = ref.read(
      meetingSuggestionControllerProvider.notifier,
    );
    final Oats o = context.oats;
    final String title = switch (s.source) {
      MeetingSource.calendar => s.event?.title ?? '',
      MeetingSource.call => LocaleKeys.meeting_suggestion_call_title.tr(),
    };
    final String detail = switch (s.source) {
      MeetingSource.calendar when s.event != null =>
        '${formatStartTime(s.event!.start)}–${formatStartTime(s.event!.end)}',
      MeetingSource.call => s.appName ?? '',
      _ => '',
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: kMeetingSuggestionWidth,
        padding: const EdgeInsets.all(OatsSpace.lg),
        decoration: BoxDecoration(
          color: o.background,
          border: Border.all(color: o.line),
          borderRadius: BorderRadius.circular(OatsRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  s.source == MeetingSource.call
                      ? Icons.call_outlined
                      : Icons.calendar_today_outlined,
                  size: OatsIconSize.md,
                  color: o.muted,
                ),
                const SizedBox(width: OatsSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: o.bodyStrong,
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: OatsIconSize.md + OatsSpace.sm,
                ),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: o.meta,
                ),
              ),
            const SizedBox(height: OatsSpace.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: OatsSpace.sm,
              runSpacing: OatsSpace.sm,
              children: <Widget>[
                OatsButton(
                  label: LocaleKeys.meeting_suggestion_dismiss.tr(),
                  onPressed: controller.dismiss,
                ),
                OatsButton(
                  icon: Icons.mic_none_outlined,
                  label: LocaleKeys.meeting_suggestion_start.tr(),
                  onPressed: controller.start,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
