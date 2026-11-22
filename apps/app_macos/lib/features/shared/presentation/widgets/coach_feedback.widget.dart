import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Affiche le retour du coach d'anglais : commentaire global puis une ligne
/// par correction (catégorie, phrase d'origine barrée, version corrigée,
/// explication).
class CoachFeedbackView extends StatelessWidget {
  /// Crée une instance de [CoachFeedbackView].
  const CoachFeedbackView({required this.feedback, super.key});

  /// Le retour du coach à afficher.
  final EnglishFeedbackEntity feedback;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String? overall = feedback.overall;
    final List<EnglishCorrectionEntity> corrections = feedback.corrections;

    if ((overall == null || overall.isEmpty) && corrections.isEmpty) {
      return Text(LocaleKeys.history_detail_coach_perfect.tr(), style: o.small);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (overall != null && overall.isNotEmpty) ...<Widget>[
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
          OatsChip(label: _categoryLabel(correction.category)),
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

  String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'grammar':
      case 'grammaire':
        return LocaleKeys.coach_category_grammar.tr();
      case 'conjugation':
      case 'conjugaison':
        return LocaleKeys.coach_category_conjugation.tr();
      case 'vocabulary':
      case 'vocabulaire':
        return LocaleKeys.coach_category_vocabulary.tr();
      case 'expression':
        return LocaleKeys.coach_category_expression.tr();
      case 'style':
        return LocaleKeys.coach_category_style.tr();
      default:
        return category.isEmpty
            ? LocaleKeys.coach_category_suggestion.tr()
            : category;
    }
  }
}
