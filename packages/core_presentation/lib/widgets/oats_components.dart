import 'package:core_presentation/theme/oats_tokens.dart';
import 'package:flutter/material.dart';

/// Titre de page en serif, actions à droite.
class OatsPageHeader extends StatelessWidget {
  /// Crée le composant.
  const OatsPageHeader({required this.title, this.trailing, super.key});

  /// Titre affiché.
  final String title;

  /// Élément aligné à droite.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: context.oats.display,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: OatsSpace.lg),
          trailing!,
        ],
      ],
    );
  }
}

/// Intertitre de section : petit, gris.
class OatsSectionHeader extends StatelessWidget {
  /// Crée le composant.
  const OatsSectionHeader(this.text, {this.trailing, super.key});

  /// Texte de l'intertitre.
  final String text;

  /// Élément aligné à droite.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OatsSpace.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: context.oats.label),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Item de la barre latérale : icône fine + libellé, pastille grise si actif.
///
/// Un seul nœud d'accessibilité (libellé + état sélectionné).
class OatsSidebarItem extends StatelessWidget {
  /// Crée le composant.
  const OatsSidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Icône à trait fin.
  final IconData icon;

  /// Libellé affiché.
  final String label;

  /// Item de la page courante.
  final bool selected;

  /// Action au clic.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? o.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(OatsRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(OatsRadius.md),
            hoverColor: o.hover,
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: OatsSpace.sm),
                child: Row(
                  children: <Widget>[
                    Icon(
                      icon,
                      size: OatsIconSize.md,
                      color: selected ? o.ink : o.muted,
                    ),
                    const SizedBox(width: OatsSpace.sm + 2),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: o.ui.copyWith(color: selected ? o.ink : o.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ligne de liste : filet en bas, survol gris très clair, bord à bord.
class OatsListRow extends StatelessWidget {
  /// Crée le composant.
  const OatsListRow({
    required this.title,
    required this.onTap,
    this.trailing,
    super.key,
  });

  /// Titre affiché.
  final String title;

  /// Méta-données à droite (heure, durée).
  final String? trailing;

  /// Action au clic.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return InkWell(
      onTap: onTap,
      hoverColor: o.hover,
      borderRadius: BorderRadius.circular(OatsRadius.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: OatsSpace.sm,
          vertical: OatsSpace.sm,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: o.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Tooltip(
                message: title,
                waitDuration: const Duration(seconds: 1),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: o.bodyStrong,
                ),
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: OatsSpace.lg),
              Text(trailing!, style: o.meta),
            ],
          ],
        ),
      ),
    );
  }
}

/// Champ de recherche bordé avec loupe.
class OatsSearchField extends StatelessWidget {
  /// Crée le composant.
  const OatsSearchField({
    required this.hint,
    required this.onChanged,
    this.controller,
    super.key,
  });

  /// Texte indicatif du champ vide.
  final String hint;

  /// Appelé à chaque frappe.
  final ValueChanged<String> onChanged;

  /// Contrôleur du texte, facultatif.
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(OatsRadius.md),
      borderSide: BorderSide(color: o.line),
    );
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.center,
        style: o.ui.copyWith(fontWeight: FontWeight.w400),
        cursorHeight: 16,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: o.ui.copyWith(color: o.faint, fontWeight: FontWeight.w400),
          isDense: true,
          filled: true,
          fillColor: o.background,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(Icons.search, size: OatsIconSize.md, color: o.faint),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: o.muted),
          ),
        ),
      ),
    );
  }
}

/// Puce bordée neutre (date, durée, interlocuteur).
class OatsChip extends StatelessWidget {
  /// Crée le composant.
  const OatsChip({required this.label, this.icon, super.key});

  /// Libellé affiché.
  final String label;

  /// Icône à trait fin, facultative.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.sm,
        vertical: OatsSpace.xxs + 1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: o.line),
        borderRadius: BorderRadius.circular(OatsRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: o.muted),
            const SizedBox(width: OatsSpace.xs),
          ],
          Text(label, style: o.meta),
        ],
      ),
    );
  }
}

/// Pastille verte du vivant (« Enregistre »), point compris.
class OatsLivePill extends StatelessWidget {
  /// Crée le composant.
  const OatsLivePill({required this.label, super.key});

  /// Libellé affiché.
  final String label;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.sm + 1,
        vertical: OatsSpace.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: o.accentSoft,
        borderRadius: BorderRadius.circular(OatsRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: o.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: OatsSpace.xs + 2),
          Text(label, style: o.meta.copyWith(color: o.accent)),
        ],
      ),
    );
  }
}

/// Puce de citation inline (« plan.md p. 4 ↗ »), teinte de l'accent.
class OatsCitationChip extends StatelessWidget {
  /// Crée le composant.
  const OatsCitationChip({required this.label, this.onTap, super.key});

  /// Libellé affiché.
  final String label;

  /// Action au clic, facultative.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Material(
      color: o.accentSoft,
      borderRadius: BorderRadius.circular(OatsRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OatsRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OatsSpace.xs + 2,
            vertical: 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: o.meta.copyWith(color: o.accent)),
              const SizedBox(width: OatsSpace.xxs),
              Icon(Icons.north_east, size: 11, color: o.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// État vide partagé : icône fine, titre, phrase, action éventuelle.
class OatsEmptyState extends StatelessWidget {
  /// Crée le composant.
  const OatsEmptyState({
    required this.icon,
    required this.message,
    this.title,
    this.action,
    super.key,
  });

  /// Icône à trait fin.
  final IconData icon;

  /// Titre en serif, facultatif.
  final String? title;

  /// Phrase explicative.
  final String message;

  /// Action proposée, facultative.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(OatsSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 28, color: o.faint),
              const SizedBox(height: OatsSpace.md),
              if (title != null) ...<Widget>[
                Text(title!, style: o.title, textAlign: TextAlign.center),
                const SizedBox(height: OatsSpace.sm),
              ],
              Text(message, style: o.small, textAlign: TextAlign.center),
              if (action != null) ...<Widget>[
                const SizedBox(height: OatsSpace.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloc d'information en ligne, bordé (modèle absent, permission refusée).
class OatsNotice extends StatelessWidget {
  /// Crée le composant.
  const OatsNotice({
    required this.icon,
    required this.message,
    this.actions = const <Widget>[],
    this.danger = false,
    super.key,
  });

  /// Icône à trait fin.
  final IconData icon;

  /// Phrase explicative.
  final String message;

  /// Boutons à la suite du message.
  final List<Widget> actions;

  /// Variante erreur ou destructive.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OatsSpace.md),
      decoration: BoxDecoration(
        border: Border.all(color: o.line),
        borderRadius: BorderRadius.circular(OatsRadius.md),
      ),
      child: Wrap(
        spacing: OatsSpace.md,
        runSpacing: OatsSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: OatsIconSize.md,
                  color: danger ? o.danger : o.muted,
                ),
              ),
              const SizedBox(width: OatsSpace.sm),
              Flexible(
                child: Text(
                  message,
                  style: o.small.copyWith(color: danger ? o.danger : o.ink),
                ),
              ),
            ],
          ),
          ...actions,
        ],
      ),
    );
  }
}
