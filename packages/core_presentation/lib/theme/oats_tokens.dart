import 'package:flutter/material.dart';

/// Police des titres et du nom de l'app (embarquée, licence OFL).
const String kOatsSerif = 'InstrumentSerif';

/// Police système macOS (San Francisco), la même que Flutter choisit par défaut.
const String kOatsSans = '.AppleSystemUIFont';

/// Espacements : multiples de 4.
abstract final class OatsSpace {
  /// 2 px.
  static const double xxs = 2;

  /// 4 px.
  static const double xs = 4;

  /// Petit.
  static const double sm = 8;

  /// Moyen.
  static const double md = 12;

  /// Grand.
  static const double lg = 16;

  /// 24 px.
  static const double xl = 24;

  /// 32 px.
  static const double xxl = 32;

  /// 48 px.
  static const double xxxl = 48;
}

/// Rayons d'angle.
abstract final class OatsRadius {
  /// Petit.
  static const double sm = 6;

  /// Moyen.
  static const double md = 8;

  /// Grand.
  static const double lg = 12;

  /// Pastille entièrement arrondie.
  static const double pill = 999;
}

/// Tailles d'icônes (trait fin).
abstract final class OatsIconSize {
  /// Petit.
  static const double sm = 14;

  /// Moyen.
  static const double md = 16;

  /// Grand.
  static const double lg = 20;
}

/// Couleurs et styles de texte d'Oats : une seule source pour tous les écrans.
///
/// Lire avec `context.oats` (repli clair/sombre si le thème n'a pas
/// l'extension, par ex. dans un test qui pompe un MaterialApp nu).
@immutable
class Oats extends ThemeExtension<Oats> {
  /// Crée un jeu de jetons.
  const Oats({
    required this.brightness,
    required this.background,
    required this.sidebar,
    required this.ink,
    required this.onInk,
    required this.muted,
    required this.faint,
    required this.line,
    required this.hover,
    required this.selected,
    required this.accent,
    required this.accentSoft,
    required this.danger,
  });

  /// Thème clair (défaut, conforme aux références).
  static const Oats light = Oats(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF7F7F5),
    ink: Color(0xFF111111),
    onInk: Color(0xFFFFFFFF),
    muted: Color(0xFF6C6E69),
    faint: Color(0xFF9C9D98),
    line: Color(0xFFE8E8E6),
    hover: Color(0xFFF4F4F2),
    selected: Color(0xFFEAEAE7),
    accent: Color(0xFF2F7D4F),
    accentSoft: Color(0xFFD9F0E0),
    danger: Color(0xFFB42318),
  );

  /// Thème sombre (suit le système).
  static const Oats dark = Oats(
    brightness: Brightness.dark,
    background: Color(0xFF121212),
    sidebar: Color(0xFF0A0A0A),
    ink: Color(0xFFF2F2EF),
    onInk: Color(0xFF111111),
    muted: Color(0xFF8B8D87),
    faint: Color(0xFF62645F),
    line: Color(0xFF262725),
    hover: Color(0xFF1B1B1A),
    selected: Color(0xFF232322),
    accent: Color(0xFFA8E6BC),
    accentSoft: Color(0xFF16261C),
    danger: Color(0xFFF0857A),
  );

  /// Clair ou sombre.
  final Brightness brightness;

  /// Fond de la zone de contenu.
  final Color background;

  /// Fond de la barre latérale.
  final Color sidebar;

  /// Texte principal, bouton plein.
  final Color ink;

  /// Texte posé sur [ink].
  final Color onInk;

  /// Texte secondaire.
  final Color muted;

  /// Texte tertiaire, indications.
  final Color faint;

  /// Filets 1 px.
  final Color line;

  /// Survol d'une ligne ou d'un bouton.
  final Color hover;

  /// Pastille de sélection (barre latérale).
  final Color selected;

  /// Accent unique, réservé au vivant (enregistrement, citation).
  final Color accent;

  /// Fond teinté de l'accent.
  final Color accentSoft;

  /// Action destructive, erreur.
  final Color danger;

  TextStyle _sans(double size, FontWeight weight, double height, Color color) =>
      TextStyle(
        fontFamily: kOatsSans,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
        letterSpacing: 0,
      );

  TextStyle _serif(double size, double letterSpacing) => TextStyle(
    fontFamily: kOatsSerif,
    package: 'core_presentation',
    fontSize: size,
    fontWeight: FontWeight.w400,
    height: 1.15,
    letterSpacing: letterSpacing,
    color: ink,
  );

  /// Titre de page (serif).
  TextStyle get display => _serif(32, -0.3);

  /// Titre de bloc ou de dialogue (serif).
  TextStyle get title => _serif(24, -0.2);

  /// Nom de l'app dans la barre latérale (serif).
  TextStyle get wordmark => _serif(22, -0.1);

  /// Intertitre en sans.
  TextStyle get heading => _sans(15, FontWeight.w600, 1.35, ink);

  /// Corps de texte.
  TextStyle get body => _sans(14, FontWeight.w400, 1.55, ink);

  /// Corps de texte appuyé (titre de ligne).
  TextStyle get bodyStrong => _sans(14, FontWeight.w500, 1.4, ink);

  /// Texte d'interface courant (boutons, items).
  TextStyle get ui => _sans(13, FontWeight.w500, 1.3, ink);

  /// Texte secondaire.
  TextStyle get small => _sans(13, FontWeight.w400, 1.45, muted);

  /// Méta-données (heures, durées) : chiffres à chasse fixe.
  TextStyle get meta => _sans(
    12,
    FontWeight.w400,
    1.3,
    muted,
  ).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);

  /// Intertitre de section (petit, gris).
  TextStyle get label => _sans(12, FontWeight.w500, 1.3, muted);

  /// Chiffre de minuteur.
  TextStyle get timer => _sans(
    20,
    FontWeight.w500,
    1.1,
    ink,
  ).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);

  @override
  Oats copyWith() => this;

  @override
  Oats lerp(Oats? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Accès aux jetons depuis un [BuildContext].
extension OatsContext on BuildContext {
  /// Jetons du thème courant.
  Oats get oats {
    final ThemeData theme = Theme.of(this);
    return theme.extension<Oats>() ??
        (theme.brightness == Brightness.dark ? Oats.dark : Oats.light);
  }
}
