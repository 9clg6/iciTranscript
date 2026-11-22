import 'package:core_presentation/theme/oats_tokens.dart';
import 'package:flutter/material.dart';

/// Petit bouton bordé, icône + libellé (« Copier », « Retour »).
class OatsButton extends StatelessWidget {
  /// Crée le composant.
  const OatsButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
    this.semanticLabel,
    super.key,
  });

  /// Libellé affiché.
  final String label;

  /// Icône à trait fin, facultative.
  final IconData? icon;

  /// Action ; null désactive le bouton.
  final VoidCallback? onPressed;

  /// Action destructive : icône et libellé dans la couleur danger.
  final bool danger;

  /// Nom accessible s'il diffère du libellé.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final ButtonStyle? style = danger
        ? OutlinedButton.styleFrom(
            foregroundColor: o.danger,
            iconColor: o.danger,
          )
        : null;
    final Widget text = Text(label, maxLines: 1, semanticsLabel: semanticLabel);
    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, style: style, child: text);
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
      label: text,
    );
  }
}

/// Bouton plein à l'encre : un seul par écran.
class OatsPrimaryButton extends StatelessWidget {
  /// Crée le composant.
  const OatsPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  /// Libellé affiché.
  final String label;

  /// Icône à trait fin, facultative.
  final IconData? icon;

  /// Action ; null désactive le bouton.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(label, maxLines: 1);
    if (icon == null) return FilledButton(onPressed: onPressed, child: text);
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: text,
    );
  }
}

/// Interrupteur : natif sur macOS, piste à l'encre quand il est actif.
class OatsSwitch extends StatelessWidget {
  /// Crée le composant.
  const OatsSwitch({required this.value, required this.onChanged, super.key});

  /// État courant.
  final bool value;

  /// Appelé au basculement ; null désactive l'interrupteur.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: o.ink,
      inactiveTrackColor: o.selected,
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ||
                o.brightness == Brightness.light
            ? o.background
            : o.muted,
      ),
    );
  }
}
