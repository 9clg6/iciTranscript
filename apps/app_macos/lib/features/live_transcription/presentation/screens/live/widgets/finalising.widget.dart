import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Après Arrêter : la transcription s'achève (rattrapage, repères). Montre
/// le temps restant et « Passer », à la place des contrôles de session.
class FinalisingWidget extends StatelessWidget {
  /// Cree une instance de [FinalisingWidget].
  const FinalisingWidget({
    required this.remaining,
    required this.onSkip,
    super.key,
  });

  /// Audio restant à transcrire.
  final Duration remaining;

  /// Arrête d'attendre : le reste devient un repère de perte.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    // Arrondi au-dessus : « ~1 s » jusqu'à la toute fin.
    final int seconds = (remaining.inMilliseconds + 999) ~/ 1000;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: OatsIconSize.md,
            child: CircularProgressIndicator(strokeWidth: 2, color: o.muted),
          ),
          const SizedBox(width: OatsSpace.sm),
          // Libellé long s'il tient, sinon le court : jamais d'ellipse
          // tant que le court tient.
          Flexible(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final String full = LocaleKeys.transcription_live_finalising
                    .tr();
                final TextPainter painter = TextPainter(
                  text: TextSpan(text: full, style: o.ui),
                  maxLines: 1,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final bool fits = painter.width <= box.maxWidth;
                painter.dispose();
                return Text(
                  fits
                      ? full
                      : LocaleKeys.transcription_live_finalising_short.tr(),
                  style: o.ui,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
          const SizedBox(width: OatsSpace.sm),
          Text(
            LocaleKeys.transcription_live_finalising_remaining.tr(
              args: <String>['$seconds'],
            ),
            style: o.small,
          ),
          const SizedBox(width: OatsSpace.md),
          OatsButton(
            icon: Icons.skip_next_outlined,
            label: LocaleKeys.transcription_live_skip_finalising.tr(),
            onPressed: onSkip,
          ),
        ],
      ),
    );
  }
}
