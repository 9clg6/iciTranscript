import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Corrections montrées pendant la réunion (les plus récentes).
const int kLiveCoachShown = 3;

/// Bloc discret du coach en direct, sous les questions : les
/// [kLiveCoachShown] dernières corrections (heure, tournure corrigée,
/// original barré) ou l'état « indisponible », jamais en rouge.
class LiveCoachBlock extends ConsumerWidget {
  /// Crée le bloc.
  const LiveCoachBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Oats o = context.oats;
    final LiveCoachSnapshot snap =
        ref.watch(liveCoachSnapshotProvider).value ??
        ref.watch(liveCoachServiceProvider).snapshot;
    final List<EnglishCorrectionEntity> all = snap.corrections;
    final List<EnglishCorrectionEntity> shown = all
        .sublist((all.length - kLiveCoachShown).clamp(0, all.length))
        .reversed
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        OatsSpace.lg,
        OatsSpace.md,
        OatsSpace.lg,
        OatsSpace.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: snap.unavailable ? o.faint : o.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: OatsSpace.xs + 2),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    snap.unavailable
                        ? LocaleKeys.coach_live_state_unavailable.tr()
                        : LocaleKeys.coach_live_option.tr(),
                    style: o.label,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: OatsSpace.sm),
          if (shown.isEmpty)
            Text(LocaleKeys.coach_live_waiting.tr(), style: o.meta)
          else
            for (final EnglishCorrectionEntity c in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: OatsSpace.sm),
                child: _LiveCorrection(c),
              ),
        ],
      ),
    );
  }
}

class _LiveCorrection extends StatelessWidget {
  const _LiveCorrection(this.correction);

  final EnglishCorrectionEntity correction;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 44,
          child: Text(
            correction.timestampMs == null
                ? ''
                : formatNoteTime(correction.timestampMs!),
            style: o.meta.copyWith(color: o.faint),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(correction.corrected, style: o.bodyStrong),
              Text(
                correction.original,
                style: o.meta.copyWith(
                  color: o.muted,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: o.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
