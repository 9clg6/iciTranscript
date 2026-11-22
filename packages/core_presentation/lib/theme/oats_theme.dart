import 'package:core_presentation/theme/oats_tokens.dart';
import 'package:flutter/material.dart';

/// Thème Material réglé sur les jetons Oats (boutons, champs, dialogues).
ThemeData buildOatsTheme(Brightness brightness) {
  final Oats o = brightness == Brightness.dark ? Oats.dark : Oats.light;
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: o.ink,
    onPrimary: o.onInk,
    secondary: o.muted,
    onSecondary: o.background,
    error: o.danger,
    onError: o.background,
    surface: o.background,
    onSurface: o.ink,
    onSurfaceVariant: o.muted,
    outline: o.line,
    outlineVariant: o.line,
    surfaceContainerLowest: o.background,
    surfaceContainerLow: o.sidebar,
    surfaceContainer: o.hover,
    surfaceContainerHigh: o.hover,
    surfaceContainerHighest: o.selected,
  );
  final RoundedRectangleBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(OatsRadius.md),
  );
  const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: OatsSpace.md,
  );
  const Size buttonSize = Size(0, 32);
  final WidgetStateProperty<Color?> overlay =
      WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> s) => s.contains(WidgetState.pressed)
            ? o.selected
            : s.contains(WidgetState.hovered)
            ? o.hover
            : null,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kOatsSans,
    scaffoldBackgroundColor: o.background,
    canvasColor: o.background,
    dividerColor: o.line,
    hoverColor: o.hover,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    extensions: <ThemeExtension<dynamic>>[o],
    dividerTheme: DividerThemeData(color: o.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: o.muted, size: OatsIconSize.md),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(o.ink),
        backgroundColor: WidgetStatePropertyAll<Color>(o.background),
        overlayColor: overlay,
        side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: o.line)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
        minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
        textStyle: WidgetStatePropertyAll<TextStyle>(o.ui),
        iconSize: const WidgetStatePropertyAll<double>(OatsIconSize.sm),
        iconColor: WidgetStatePropertyAll<Color>(o.muted),
        elevation: const WidgetStatePropertyAll<double>(0),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(o.onInk),
        backgroundColor: WidgetStatePropertyAll<Color>(o.ink),
        overlayColor: WidgetStatePropertyAll<Color>(
          o.onInk.withValues(alpha: 0.08),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
        minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
        textStyle: WidgetStatePropertyAll<TextStyle>(o.ui),
        iconSize: const WidgetStatePropertyAll<double>(OatsIconSize.sm),
        iconColor: WidgetStatePropertyAll<Color>(o.onInk),
        elevation: const WidgetStatePropertyAll<double>(0),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(o.ink),
        overlayColor: overlay,
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
        minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
        textStyle: WidgetStatePropertyAll<TextStyle>(o.ui),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? o.ink : o.selected,
      ),
      thumbColor: WidgetStatePropertyAll<Color>(o.background),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(
        Colors.transparent,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: o.muted,
      linearTrackColor: o.line,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: o.ink,
        borderRadius: BorderRadius.circular(OatsRadius.sm),
      ),
      textStyle: o.meta.copyWith(color: o.onInk),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: o.background,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OatsRadius.lg),
        side: BorderSide(color: o.line),
      ),
      titleTextStyle: o.heading,
      contentTextStyle: o.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: o.ink,
      contentTextStyle: o.ui.copyWith(color: o.onInk),
      elevation: 0,
      width: 420,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OatsRadius.md),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: o.ui),
    popupMenuTheme: PopupMenuThemeData(
      color: o.background,
      surfaceTintColor: Colors.transparent,
      textStyle: o.ui,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OatsRadius.md),
        side: BorderSide(color: o.line),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: o.ink,
      selectionColor: o.selected,
    ),
  );
}
