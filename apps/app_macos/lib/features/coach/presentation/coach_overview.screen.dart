import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/coach/presentation/coach_overview.provider.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart'
    show kContentMaxWidth;
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Page « Coach anglais » : les notes passées au coach (jour par jour, avec
/// leur nombre de corrections), puis les erreurs récurrentes.
class CoachOverviewScreen extends ConsumerWidget {
  /// Crée la page ; [onOpen] ouvre une note (sur sa section coach).
  const CoachOverviewScreen({required this.onOpen, super.key});

  /// Ouvre la note d'id donné.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CoachOverview> async = ref.watch(coachOverviewProvider);
    final Widget header = _Column(
      child: OatsPageHeader(title: LocaleKeys.nav_coach.tr()),
    );
    final CoachOverview? data = async.hasError ? null : async.value;
    if (data == null || data.notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OatsSpace.xxxl,
          vertical: OatsSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(
              child: async.hasError
                  ? OatsEmptyState(
                      icon: Icons.error_outline,
                      message: LocaleKeys.common_error_generic.tr(),
                      action: OatsButton(
                        label: LocaleKeys.common_action_retry.tr(),
                        onPressed: () => ref.invalidate(coachOverviewProvider),
                      ),
                    )
                  : data == null
                  ? const Center(child: CircularProgressIndicator())
                  : OatsEmptyState(
                      icon: Icons.school_outlined,
                      message: LocaleKeys.coach_empty.tr(),
                    ),
            ),
          ],
        ),
      );
    }

    final Oats o = context.oats;
    final DateTime now = ref.watch(nowProvider)();
    final List<Widget> days = <Widget>[];
    DateTime? day;
    for (final CoachNote n in data.notes) {
      final DateTime d = DateTime(
        n.session.createdAt.year,
        n.session.createdAt.month,
        n.session.createdAt.day,
      );
      if (d != day) {
        day = d;
        days.add(
          Padding(
            padding: EdgeInsets.only(
              left: OatsSpace.sm,
              top: days.isEmpty ? 0 : OatsSpace.xl,
              bottom: OatsSpace.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(formatDayHeader(d, now: now), style: o.label),
            ),
          ),
        );
      }
      final int count = n.feedback.corrections.length;
      days.add(
        OatsListRow(
          title: n.session.title,
          trailing: count > 0
              ? LocaleKeys.coach_corrections.plural(count)
              : n.feedback.unanalyzedSegmentIds.isNotEmpty
              ? LocaleKeys.coach_unanalyzed.tr()
              : n.feedback.nothingToAnalyse
              ? LocaleKeys.coach_nothing_to_analyse.tr()
              : LocaleKeys.coach_no_correction.tr(),
          onTap: () => onOpen(n.session.id),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.xxxl,
        vertical: OatsSpace.xl,
      ),
      children: <Widget>[
        header,
        const SizedBox(height: OatsSpace.xxl),
        _Column(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: days,
          ),
        ),
        if (data.recurring.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.xxl),
          _Column(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: OatsSpace.sm),
                  child: OatsSectionHeader(
                    LocaleKeys.coach_recurring_title.tr(),
                  ),
                ),
                for (final RecurringMistake r in data.recurring)
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: OatsSpace.sm,
                      vertical: OatsSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: o.line)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            coachCategoryLabel(r.category),
                            style: o.bodyStrong,
                          ),
                        ),
                        Text(
                          LocaleKeys.coach_recurring_notes.plural(r.notes),
                          style: o.meta,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Colonne centrée de largeur de lecture.
class _Column extends StatelessWidget {
  const _Column({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      child: child,
    ),
  );
}
