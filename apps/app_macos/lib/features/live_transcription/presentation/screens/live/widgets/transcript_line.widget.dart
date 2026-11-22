import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Une ligne de transcription en direct : qui parle, quand, le texte, puis la
/// traduction éventuelle.
class TranscriptLineWidget extends StatelessWidget {
  /// Cree une instance de [TranscriptLineWidget].
  const TranscriptLineWidget({
    required this.segment,
    this.translation,
    this.speaker,
    super.key,
  });

  /// Le segment de transcription a afficher.
  final TranscriptSegmentEntity segment;

  /// Traduction du texte (sous-titre), null si absente/désactivée.
  final String? translation;

  /// Interlocuteur identifié en direct (0, 1, …), null si inconnu.
  final int? speaker;

  String _formatTimestamp(int timestampMs) {
    final Duration d = Duration(milliseconds: timestampMs);
    final String hours = d.inHours.toString().padLeft(2, '0');
    final String minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final bool isInput = segment.source == AudioSource.input;
    final int? who = isInput ? null : speaker;
    final String label = isInput
        ? LocaleKeys.transcription_live_speaker_me.tr()
        : who != null
        ? LocaleKeys.transcription_live_speaker_n.tr(
            args: <String>['${who + 1}'],
          )
        : LocaleKeys.transcription_live_speaker_system.tr();
    final String? t = translation?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: o.label.copyWith(color: isInput ? o.ink : o.muted),
            ),
            const SizedBox(width: OatsSpace.sm),
            Text(
              _formatTimestamp(segment.timestampMs),
              style: o.meta.copyWith(color: o.faint),
            ),
          ],
        ),
        const SizedBox(height: OatsSpace.xs),
        Text(segment.text, style: o.body),
        if (t != null && t.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.translate, size: 13, color: o.faint),
              ),
              const SizedBox(width: OatsSpace.xs + 2),
              Expanded(child: Text(translation!, style: o.small)),
            ],
          ),
        ],
      ],
    );
  }
}
