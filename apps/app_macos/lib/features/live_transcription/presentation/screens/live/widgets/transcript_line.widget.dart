import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Widget affichant une ligne de transcription avec timestamp et badge source.
///
/// Affiche le badge colore [MOI] ou [SYSTEME], le timestamp
/// et le texte transcrit dans un conteneur style.
class TranscriptLineWidget extends StatelessWidget {
  /// Cree une instance de [TranscriptLineWidget].
  const TranscriptLineWidget({
    required this.segment,
    this.translation,
    super.key,
  });

  /// Le segment de transcription a afficher.
  final TranscriptSegmentEntity segment;

  /// Traduction du texte (sous-titre), null si absente/désactivée.
  final String? translation;

  String _formatTimestamp(int timestampMs) {
    final Duration duration = Duration(milliseconds: timestampMs);
    final String hours = duration.inHours.toString().padLeft(2, '0');
    final String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isInput = segment.source == AudioSource.input;

    final Color badgeBackgroundColor = isInput
        ? colorScheme.primaryContainer.withValues(alpha: 0.15)
        : colorScheme.tertiaryContainer.withValues(alpha: 0.15);

    final Color badgeTextColor = isInput
        ? colorScheme.primary
        : colorScheme.tertiary;

    final String badgeLabel = isInput
        ? LocaleKeys.transcription_live_speaker_me.tr()
        : LocaleKeys.transcription_live_speaker_system.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Header: badge + timestamp
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBackgroundColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badgeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badgeTextColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  fontSize: 10,
                ),
              ),
            ),
            const Gap(12),
            Text(
              _formatTimestamp(segment.timestampMs),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const Gap(8),
        // Text content
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: isInput
              ? BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.1),
                  ),
                )
              : BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: colorScheme.tertiary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                segment.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isInput
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  height: 1.6,
                  fontSize: 15,
                  fontStyle: isInput ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              if (translation != null && translation!.trim().isNotEmpty) ...
                  <Widget>[
                const Gap(6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.translate,
                      size: 13,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    const Gap(6),
                    Expanded(
                      child: Text(
                        translation!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary.withValues(alpha: 0.85),
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
