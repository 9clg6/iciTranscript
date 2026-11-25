import 'package:ici_transcript/core/platform/prefs_store.dart';

/// Où va le texte dicté.
enum DictationOutputMode { paste, clipboard }

/// Raccourci de dictée : code de touche macOS + masque de modificateurs
/// Carbon (cmd 256, shift 512, option 2048, control 4096).
class DictationShortcut {
  const DictationShortcut({required this.keyCode, required this.modifiers});

  /// ⌃⌥Espace (⌥Espace seul tape une espace insécable sur clavier
  /// français).
  static const DictationShortcut controlOptionSpace = DictationShortcut(
    keyCode: 49,
    modifiers: 4096 | 2048,
  );

  /// Code de touche macOS ; null : modificateurs seuls (⌘⌥), surveillés
  /// par le plugin (Accessibilité requise), Carbon ne sachant pas les poser.
  final int? keyCode;

  /// Masques Carbon (HIToolbox Events.h).
  static const int command = 256;
  static const int shift = 512;
  static const int option = 2048;
  static const int control = 4096;

  /// Modificateurs seuls utilisables : au moins deux parmi ⌃⌥⇧⌘, dont ⌃, ⌥
  /// ou ⌘ (⇧ seul ou un seul modificateur volerait une frappe ordinaire).
  static bool isValidModifiersOnly(int modifiers) {
    const int all = command | shift | option | control;
    if (modifiers & ~all != 0) return false;
    int count = 0;
    for (final int bit in <int>[command, shift, option, control]) {
      if (modifiers & bit != 0) count++;
    }
    return count >= 2 && modifiers & (command | option | control) != 0;
  }

  final int modifiers;
}

/// Réglages de la dictée.
class DictationSettings {
  const DictationSettings({
    this.enabled = true,
    this.shortcut = DictationShortcut.controlOptionSpace,
    this.outputMode = DictationOutputMode.paste,
  });

  final bool enabled;
  final DictationShortcut shortcut;
  final DictationOutputMode outputMode;
}

/// Lit et écrit les réglages de la dictée dans prefs.json, via le
/// [PrefsStore] partagé (les autres clés sont gardées).
class DictationPreferences {
  /// Crée les préférences sur [store] (défaut : prefs.json de l'app).
  DictationPreferences([PrefsStore? store]) : _store = store ?? PrefsStore();

  static const String _enabled = 'dictation_enabled';
  static const String _keyCode = 'dictation_key_code';
  static const String _modifiers = 'dictation_modifiers';
  static const String _outputMode = 'dictation_output_mode';

  final PrefsStore _store;

  /// Réglages enregistrés ; défauts pour tout champ absent ou illisible.
  Future<DictationSettings> load() async {
    final Map<String, Object?> json = await _store.read();
    const DictationSettings d = DictationSettings();
    final Object? keyCode = json[_keyCode];
    final int? modifiers = prefValue<int>(json, _modifiers);
    // Clé absente avec des modificateurs valides : modificateurs seuls. Une
    // clé présente mais illisible n'est jamais lue comme telle.
    final bool modifiersOnly =
        !json.containsKey(_keyCode) &&
        modifiers != null &&
        DictationShortcut.isValidModifiersOnly(modifiers);
    return DictationSettings(
      enabled: prefValue<bool>(json, _enabled) ?? d.enabled,
      shortcut: keyCode is int && modifiers != null
          ? DictationShortcut(keyCode: keyCode, modifiers: modifiers)
          : modifiersOnly
          ? DictationShortcut(keyCode: null, modifiers: modifiers)
          : d.shortcut,
      outputMode:
          DictationOutputMode.values.asNameMap()[json[_outputMode]] ??
          d.outputMode,
    );
  }

  /// Enregistre [settings] sans toucher aux autres clés de prefs.json.
  Future<void> save(DictationSettings settings) =>
      _store.update(<String, Object?>{
        _enabled: settings.enabled,
        _keyCode: settings.shortcut.keyCode,
        _modifiers: settings.shortcut.modifiers,
        _outputMode: settings.outputMode.name,
      });
}
