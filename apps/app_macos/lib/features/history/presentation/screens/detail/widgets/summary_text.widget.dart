import 'package:core_presentation/core_presentation.dart';
import 'package:flutter/material.dart';

/// Résumé du modèle rendu avec une hiérarchie typographique simple :
/// intertitres (`#`), puces (`-`, `*`, `•`, `1.`), paragraphes, `**gras**`.
// ponytail: sous-ensemble Markdown que produisent nos prompts ; un vrai
// moteur Markdown si les résumés gagnent tableaux ou liens.
class SummaryText extends StatelessWidget {
  /// Crée le rendu de [text].
  const SummaryText(this.text, {super.key});

  /// Texte brut du résumé.
  final String text;

  static final RegExp _bullet = RegExp(r'^([-*•]|\d+[.)])\s+');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+');

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final List<Widget> children = <Widget>[];
    for (final String raw in text.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      if (_heading.hasMatch(line)) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : OatsSpace.lg,
              bottom: OatsSpace.xs,
            ),
            child: Text(
              line.replaceFirst(_heading, '').replaceAll('**', ''),
              style: o.heading,
            ),
          ),
        );
      } else if (_bullet.hasMatch(line)) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: OatsSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: OatsSpace.lg,
                  child: Text('•', style: o.body.copyWith(color: o.faint)),
                ),
                Expanded(child: _rich(line.replaceFirst(_bullet, ''), o)),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: OatsSpace.sm),
            child: _rich(line, o),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// `**gras**` en graisse 600, le reste en corps normal.
  Widget _rich(String line, Oats o) {
    final List<String> parts = line.split('**');
    return Text.rich(
      TextSpan(
        style: o.body,
        children: <TextSpan>[
          for (int i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
        ],
      ),
    );
  }
}
