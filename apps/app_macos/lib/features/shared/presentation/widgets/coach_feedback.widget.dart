import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Affiche le retour du coach d'anglais sous forme de cartes de correction.
///
/// Chaque correction montre la catégorie, la phrase d'origine barrée,
/// la version corrigée et une explication. Un commentaire global
/// optionnel est affiché en tête.
class CoachFeedbackView extends StatelessWidget {
  /// Crée une instance de [CoachFeedbackView].
  const CoachFeedbackView({required this.feedback, super.key});

  /// Le retour du coach à afficher.
  final EnglishFeedbackEntity feedback;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final String? overall = feedback.overall;
    final List<EnglishCorrectionEntity> corrections = feedback.corrections;

    if ((overall == null || overall.isEmpty) && corrections.isEmpty) {
      return Text(
        'Aucune correction : votre anglais est impeccable.',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (overall != null && overall.isNotEmpty) ...<Widget>[
          Text(
            overall,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              height: 1.4,
            ),
          ),
          const Gap(12),
        ],
        for (final EnglishCorrectionEntity correction in corrections) ...<Widget>[
          _CorrectionCard(correction: correction),
          const Gap(8),
        ],
      ],
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({required this.correction});

  final EnglishCorrectionEntity correction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color categoryColor = _categoryColor(correction.category, colorScheme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _categoryLabel(correction.category),
              style: textTheme.labelSmall?.copyWith(
                color: categoryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Gap(8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  correction.original,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  correction.corrected,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (correction.explanation.isNotEmpty) ...<Widget>[
            const Gap(6),
            Text(
              correction.explanation,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(String category, ColorScheme colorScheme) {
    switch (category.toLowerCase()) {
      case 'grammar':
      case 'grammaire':
      case 'conjugation':
      case 'conjugaison':
        return colorScheme.error;
      case 'vocabulary':
      case 'vocabulaire':
        return colorScheme.tertiary;
      case 'expression':
      case 'style':
        return colorScheme.primary;
      default:
        return colorScheme.secondary;
    }
  }

  String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'grammar':
      case 'grammaire':
        return 'Grammaire';
      case 'conjugation':
      case 'conjugaison':
        return 'Conjugaison';
      case 'vocabulary':
      case 'vocabulaire':
        return 'Vocabulaire';
      case 'expression':
        return 'Expression';
      case 'style':
        return 'Style';
      default:
        return category.isEmpty ? 'Suggestion' : category;
    }
  }
}
