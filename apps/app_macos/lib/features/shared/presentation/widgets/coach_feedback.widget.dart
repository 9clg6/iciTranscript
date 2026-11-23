import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Affiche le retour du coach d'anglais : commentaire global puis une ligne
/// par correction (catégorie, heure dans la note, phrase d'origine barrée,
/// version corrigée, explication) ; « Aucune correction » si rien n'a été
/// trouvé ; la mention d'une partie non analysée, avec « Réessayer » si
/// [onRetry] est fourni.
class CoachFeedbackView extends StatelessWidget {
  /// Crée une instance de [CoachFeedbackView].
  const CoachFeedbackView({required this.feedback, this.onRetry, super.key});

  /// Le retour du coach à afficher.
  final EnglishFeedbackEntity feedback;

  /// Relance les phrases non analysées ; null : pas de bouton.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String? overall = feedback.overall;
    final List<EnglishCorrectionEntity> corrections = feedback.corrections;

    final bool unanalyzed = feedback.unanalyzedSegmentIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (unanalyzed) ...<Widget>[
          OatsNotice(
            icon: Icons.info_outline,
            message: LocaleKeys.coach_unanalyzed.tr(),
            actions: <Widget>[
              if (onRetry != null)
                OatsButton(
                  label: LocaleKeys.common_action_retry.tr(),
                  onPressed: onRetry,
                ),
            ],
          ),
          const SizedBox(height: OatsSpace.md),
        ],
        if (corrections.isEmpty && !unanalyzed)
          Text(
            feedback.nothingToAnalyse
                ? LocaleKeys.coach_nothing_to_analyse.tr()
                : LocaleKeys.history_detail_coach_perfect.tr(),
            style: o.small,
          )
        else if (overall != null && overall.isNotEmpty) ...<Widget>[
          Text(overall, style: o.body),
          const SizedBox(height: OatsSpace.md),
        ],
        for (final EnglishCorrectionEntity c in corrections)
          _CorrectionRow(correction: c),
      ],
    );
  }
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({required this.correction});

  final EnglishCorrectionEntity correction;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: OatsSpace.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              OatsChip(label: coachCategoryLabel(correction.category)),
              if (correction.timestampMs case final int ms) ...<Widget>[
                const SizedBox(width: OatsSpace.sm),
                Text(formatNoteTime(ms), style: o.meta.copyWith(color: o.faint)),
              ],
            ],
          ),
          const SizedBox(height: OatsSpace.sm),
          Text(
            correction.original,
            style: o.body.copyWith(
              color: o.muted,
              decoration: TextDecoration.lineThrough,
              decorationColor: o.muted,
            ),
          ),
          Text(correction.corrected, style: o.bodyStrong),
          if (correction.explanation.isNotEmpty) ...<Widget>[
            const SizedBox(height: OatsSpace.xs),
            Text(correction.explanation, style: o.small),
          ],
        ],
      ),
    );
  }
}

/// Clé de traduction de [category] (« grammar » et « Grammaire » sont la
/// même) ; null : catégorie libre du modèle, affichée telle quelle.
String? coachCategoryKey(String category) =>
    switch (category.trim().toLowerCase()) {
      'grammar' || 'grammaire' => LocaleKeys.coach_category_grammar,
      'conjugation' || 'conjugaison' => LocaleKeys.coach_category_conjugation,
      'vocabulary' || 'vocabulaire' => LocaleKeys.coach_category_vocabulary,
      'expression' => LocaleKeys.coach_category_expression,
      'style' => LocaleKeys.coach_category_style,
      '' => LocaleKeys.coach_category_suggestion,
      _ => null,
    };

/// Libellé affiché de [category].
String coachCategoryLabel(String category) =>
    coachCategoryKey(category)?.tr() ?? category;

/// Heure dans la note « mm:ss », comme les tours de la transcription.
String formatNoteTime(int ms) {
  final Duration at = Duration(milliseconds: ms);
  return '${at.inMinutes.toString().padLeft(2, '0')}:'
      '${(at.inSeconds % 60).toString().padLeft(2, '0')}';
}
