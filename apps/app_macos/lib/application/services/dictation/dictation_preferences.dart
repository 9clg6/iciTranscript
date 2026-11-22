import 'dart:convert';
import 'dart:io';

import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Où va le texte dicté.
enum DictationOutputMode { paste, clipboard }

/// Raccourci de dictée : code de touche macOS + masque de modificateurs
/// Carbon (cmd 256, shift 512, option 2048, control 4096).
class DictationShortcut {
  const DictationShortcut({required this.keyCode, required this.modifiers});

  /// ⌥Espace.
  static const DictationShortcut optionSpace = DictationShortcut(
    keyCode: 49,
    modifiers: 2048,
  );

  final int keyCode;
  final int modifiers;
}

/// Réglages de la dictée.
class DictationSettings {
  const DictationSettings({
    this.enabled = true,
    this.shortcut = DictationShortcut.optionSpace,
    this.outputMode = DictationOutputMode.paste,
  });

  final bool enabled;
  final DictationShortcut shortcut;
  final DictationOutputMode outputMode;
}

/// Lit et écrit les réglages de la dictée dans prefs.json, à côté des
/// autres réglages (les clés inconnues sont gardées).
class DictationPreferences {
  static const String _enabled = 'dictation_enabled';
  static const String _keyCode = 'dictation_key_code';
  static const String _modifiers = 'dictation_modifiers';
  static const String _outputMode = 'dictation_output_mode';

  File get _file => File('${appDataDirectory()}/prefs.json');

  /// Réglages enregistrés ; défauts pour tout champ absent ou illisible.
  Future<DictationSettings> load() async {
    final Map<String, dynamic> json = await _read();
    const DictationSettings d = DictationSettings();
    final Object? keyCode = json[_keyCode];
    final Object? modifiers = json[_modifiers];
    return DictationSettings(
      enabled: json[_enabled] is bool ? json[_enabled] as bool : d.enabled,
      shortcut: keyCode is int && modifiers is int
          ? DictationShortcut(keyCode: keyCode, modifiers: modifiers)
          : d.shortcut,
      outputMode: DictationOutputMode.values.asNameMap()[json[_outputMode]] ??
          d.outputMode,
    );
  }

  /// Enregistre [settings] sans toucher aux autres clés de prefs.json.
  Future<void> save(DictationSettings settings) async {
    final Map<String, dynamic> json = await _read()
      ..addAll(<String, Object>{
        _enabled: settings.enabled,
        _keyCode: settings.shortcut.keyCode,
        _modifiers: settings.shortcut.modifiers,
        _outputMode: settings.outputMode.name,
      });
    final File f = _file;
    await f.parent.create(recursive: true);
    // Écriture atomique : un fichier à moitié écrit perdrait tous les réglages.
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(f.path);
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final Object? json = jsonDecode(await _file.readAsString());
      return json is Map<String, dynamic> ? json : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }
}
