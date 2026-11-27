import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_word_diff.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Affiche le retour du coach d'anglais : commentaire global, bilan chiffré
/// par type, corrections groupées par type (repliables) avec le diff mot à
/// mot (mots dits barrés, mots corrigés en gras), puis « Vocabulaire à
/// retenir » tiré des corrections vocabulaire et expression. Une correction
/// identique à l'original est masquée ; « Aucune correction » si rien n'a été
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
    final List<EnglishCorrectionEntity> corrections =
        feedback.meaningfulCorrections;
    final List<_CoachGroup> groups = _groupByCategory(corrections);
    final vocabulary = _vocabulary(corrections);

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
        if (corrections.isNotEmpty) ...<Widget>[
          _Recap(key: const ValueKey<String>('coach-recap'), groups: groups),
          const SizedBox(height: OatsSpace.md),
          for (final _CoachGroup g in groups)
            _CollapsibleGroup(key: ValueKey<String>(g.key), group: g),
        ],
        if (vocabulary.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.lg),
          _VocabularySection(
            key: const ValueKey<String>('coach-vocabulary'),
            items: vocabulary,
          ),
        ],
      ],
    );
  }
}

/// Les corrections d'un même type, sous son libellé.
class _CoachGroup {
  _CoachGroup(this.key, this.label);

  /// Clé de traduction du type, ou catégorie libre telle quelle.
  final String key;
  final String label;
  final List<EnglishCorrectionEntity> items = <EnglishCorrectionEntity>[];
}

/// Ordre fixe des types ; les catégories libres suivent, dans l'ordre
/// d'arrivée.
final List<String> _categoryOrder = <String>[
  LocaleKeys.coach_category_grammar,
  LocaleKeys.coach_category_expression,
  LocaleKeys.coach_category_vocabulary,
  LocaleKeys.coach_category_conjugation,
  LocaleKeys.coach_category_style,
  LocaleKeys.coach_category_suggestion,
];

List<_CoachGroup> _groupByCategory(List<EnglishCorrectionEntity> corrections) {
  final Map<String, _CoachGroup> byKey = <String, _CoachGroup>{};
  for (final EnglishCorrectionEntity c in corrections) {
    final String key = coachCategoryKey(c.category) ?? c.category;
    byKey
        .putIfAbsent(
          key,
          () => _CoachGroup(key, coachCategoryLabel(c.category)),
        )
        .items
        .add(c);
  }
  return <_CoachGroup>[
    for (final String k in _categoryOrder)
      if (byKey[k] != null) byKey[k]!,
    for (final _CoachGroup g in byKey.values)
      if (!_categoryOrder.contains(g.key)) g,
  ];
}

/// Tournures à retenir, dans l'ordre de la note : corrections vocabulaire
/// et expression ; terme = mots ajoutés (sinon le corrigé entier), sans
/// doublon (casse près), puis les [kVocabularyMax] premiers.
List<({String term, String explanation})> _vocabulary(
  List<EnglishCorrectionEntity> corrections,
) {
  final Set<String> seen = <String>{};
  final List<({String term, String explanation})> out =
      <({String term, String explanation})>[];
  for (final EnglishCorrectionEntity c in corrections) {
    final String? key = coachCategoryKey(c.category);
    if (key != LocaleKeys.coach_category_vocabulary &&
        key != LocaleKeys.coach_category_expression) {
      continue;
    }
    final String added = <String>[
      for (final CoachDiffToken t in coachWordDiff(c.original, c.corrected))
        if (t.kind == CoachDiffKind.added) t.text,
    ].join(' ');
    final String term = added.isEmpty ? c.corrected : added;
    if (seen.add(term.trim().toLowerCase())) {
      out.add((term: term, explanation: c.explanation));
    }
  }
  return out.take(kVocabularyMax).toList();
}

/// Nombre maximal de termes sous « Vocabulaire à retenir ».
const int kVocabularyMax = 8;

class _Recap extends StatelessWidget {
  const _Recap({required this.groups, super.key});

  final List<_CoachGroup> groups;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Wrap(
      spacing: OatsSpace.lg,
      runSpacing: OatsSpace.xs,
      children: <Widget>[
        for (final _CoachGroup g in groups)
          Text.rich(
            TextSpan(
              text: '${g.label} ',
              style: o.small,
              children: <InlineSpan>[
                TextSpan(text: '${g.items.length}', style: o.bodyStrong),
              ],
            ),
          ),
      ],
    );
  }
}

class _CollapsibleGroup extends StatefulWidget {
  const _CollapsibleGroup({required this.group, super.key});

  final _CoachGroup group;

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final _CoachGroup g = widget.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          label: '${g.label} ${g.items.length}',
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: OatsSpace.sm),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _open ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: o.muted,
                    ),
                    const SizedBox(width: OatsSpace.xs),
                    Text(g.label, style: o.bodyStrong),
                    const SizedBox(width: OatsSpace.sm),
                    Text(
                      '${g.items.length}',
                      style: o.meta.copyWith(color: o.faint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          for (final EnglishCorrectionEntity c in g.items)
            _CorrectionRow(correction: c),
      ],
    );
  }
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({required this.correction});

  final EnglishCorrectionEntity correction;

  /// Les mots d'un côté du diff ; ceux qui ne sont que de ce côté ([own])
  /// prennent [highlight], les autres le style de base.
  Text _line(
    List<CoachDiffToken> tokens,
    CoachDiffKind own,
    TextStyle base,
    TextStyle highlight,
  ) {
    final List<CoachDiffToken> side = <CoachDiffToken>[
      for (final CoachDiffToken t in tokens)
        if (t.kind == own || t.kind == CoachDiffKind.same) t,
    ];
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          for (int i = 0; i < side.length; i++) ...<InlineSpan>[
            if (i > 0) const TextSpan(text: ' '),
            TextSpan(
              text: side[i].text,
              style: side[i].kind == own ? highlight : null,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final List<CoachDiffToken> tokens = coachWordDiff(
      correction.original,
      correction.corrected,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: OatsSpace.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (correction.timestampMs case final int ms) ...<Widget>[
            Text(formatNoteTime(ms), style: o.meta.copyWith(color: o.faint)),
            const SizedBox(height: OatsSpace.xs),
          ],
          _line(
            tokens,
            CoachDiffKind.removed,
            o.body.copyWith(color: o.muted),
            TextStyle(
              color: o.danger,
              decoration: TextDecoration.lineThrough,
              decorationColor: o.danger,
            ),
          ),
          _line(
            tokens,
            CoachDiffKind.added,
            o.body,
            TextStyle(color: o.accent, fontWeight: FontWeight.w600),
          ),
          if (correction.explanation.isNotEmpty) ...<Widget>[
            const SizedBox(height: OatsSpace.xs),
            Text(correction.explanation, style: o.small),
          ],
        ],
      ),
    );
  }
}

class _VocabularySection extends StatelessWidget {
  const _VocabularySection({required this.items, super.key});

  final List<({String term, String explanation})> items;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(LocaleKeys.coach_vocabulary_title.tr(), style: o.bodyStrong),
        for (final ({String term, String explanation}) v in items)
          Padding(
            padding: const EdgeInsets.only(top: OatsSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(v.term, style: o.bodyStrong),
                if (v.explanation.isNotEmpty)
                  Text(v.explanation, style: o.small),
              ],
            ),
          ),
      ],
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
