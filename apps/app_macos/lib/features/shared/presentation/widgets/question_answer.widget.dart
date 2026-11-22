import 'package:core_presentation/core_presentation.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';

/// Une question et sa réponse proposée : qui, quand, la question, la
/// réponse en texte nu avec ses citations en puces inline, l'état, puis les
/// sources en puces bordées. Commun au direct et à la note.
class QuestionAnswerView extends StatelessWidget {
  /// Crée la vue.
  const QuestionAnswerView({
    required this.question,
    required this.speakerLabel,
    this.status,
    this.statusTone = QuestionStatusTone.neutral,
    this.truncatedLabel,
    this.actions = const <Widget>[],
    this.footer = const <Widget>[],
    super.key,
  });

  /// La question.
  final LiveQuestion question;

  /// « Interlocuteur 2 », « Vous »…
  final String speakerLabel;

  /// Ligne d'état sous la question (en cours, refus, échec…), facultative.
  final String? status;

  /// Teinte de [status].
  final QuestionStatusTone statusTone;

  /// Mention d'une réponse coupée, affichée si la réponse l'est.
  final String? truncatedLabel;

  /// Petites actions à droite de l'en-tête (icônes à info-bulle).
  final List<Widget> actions;

  /// Boutons sous la réponse.
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String? s = status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$speakerLabel · '
                '${TranscriptFormatter.timestamp(question.timestampMs)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: o.meta,
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: OatsSpace.xs),
        Text(question.text, style: o.bodyStrong),
        if (question.answer.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.sm),
          AnswerText(question.answer, sources: question.sources),
        ],
        if (s != null) ...<Widget>[
          const SizedBox(height: OatsSpace.sm),
          _StatusLine(s, tone: statusTone),
        ],
        if (question.truncated && truncatedLabel != null) ...<Widget>[
          const SizedBox(height: OatsSpace.xs),
          Row(
            children: <Widget>[
              Icon(
                Icons.content_cut_outlined,
                size: OatsIconSize.sm,
                color: o.faint,
              ),
              const SizedBox(width: OatsSpace.xs),
              Flexible(
                child: Text(
                  truncatedLabel!,
                  style: o.meta.copyWith(color: o.faint),
                ),
              ),
            ],
          ),
        ],
        if (question.sources.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.sm),
          Wrap(
            spacing: OatsSpace.xs + 2,
            runSpacing: OatsSpace.xs + 2,
            children: <Widget>[
              for (int i = 0; i < question.sources.length; i++)
                Tooltip(
                  message: question.sources[i].excerpt,
                  child: OatsChip(
                    icon: Icons.description_outlined,
                    label: '${i + 1}  ${question.sources[i].title}',
                  ),
                ),
            ],
          ),
        ],
        if (footer.isNotEmpty) ...<Widget>[
          const SizedBox(height: OatsSpace.sm),
          Wrap(
            spacing: OatsSpace.sm,
            runSpacing: OatsSpace.sm,
            children: footer,
          ),
        ],
      ],
    );
  }
}

/// Teinte de la ligne d'état : neutre, vivante (accent) ou en échec.
enum QuestionStatusTone {
  /// Gris.
  neutral,

  /// Accent vert, réservé au vivant (réponse en cours).
  live,

  /// Erreur.
  danger,
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.text, {required this.tone});

  final String text;
  final QuestionStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final Color c = switch (tone) {
      QuestionStatusTone.neutral => o.muted,
      QuestionStatusTone.live => o.accent,
      QuestionStatusTone.danger => o.danger,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tone == QuestionStatusTone.live) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: OatsSpace.xs + 2),
        ],
        Flexible(child: Text(text, style: o.small.copyWith(color: c))),
      ],
    );
  }
}

/// Réponse en texte nu : une puce « • » par ligne « - », chaque `[S<n>]`
/// vers une source connue devient une puce de citation inline ; les autres
/// repères (flux en cours, citation inconnue) ne s'affichent pas.
class AnswerText extends StatelessWidget {
  /// Crée le texte.
  const AnswerText(this.answer, {required this.sources, super.key});

  /// Réponse, partielle ou finale.
  final String answer;

  /// Sources citées, `[S1]` = la première.
  final List<AnswerSource> sources;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String display = answer.replaceAll(
      RegExp(r'^- ', multiLine: true),
      '•  ',
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    int at = 0;
    for (final RegExpMatch m in kCitation.allMatches(display)) {
      spans.add(TextSpan(text: display.substring(at, m.start).trimRight()));
      at = m.end;
      final int n = int.parse(m[1]!);
      if (n < 1 || n > sources.length) continue;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: OatsSpace.xs),
            child: Tooltip(
              message: sources[n - 1].title,
              child: OatsCitationChip(label: '$n'),
            ),
          ),
        ),
      );
    }
    spans.add(TextSpan(text: display.substring(at)));
    return Text.rich(TextSpan(children: spans), style: o.body);
  }
}

/// [answer] sans repères de citation, pour le presse-papiers.
String answerPlainText(String answer) =>
    answer.replaceAll(RegExp(r'\s*\[S\d+\]'), '');
