import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Raccourci de dictée « modificateurs seuls » (⌘⌥, sans autre touche) dans
/// prefs.json.
///
/// Stockage choisi :
/// - modèle : `DictationShortcut(keyCode: null, modifiers: <masque Carbon>)`,
///   `keyCode` null = modificateurs seuls ;
/// - prefs.json : `dictation_modifiers` présent, `dictation_key_code` ABSENT
///   (le `PrefsStore` retire une clé de valeur null ; aucune clé nouvelle).
///   Un sentinelle (-1) est écarté : la version actuelle le passerait à
///   `UInt32(keyCode)` côté Swift, qui plante sur un négatif. Avec la clé
///   absente, une version plus ancienne relit simplement ⌃⌥Espace ;
/// - un prefs.json d'avant (code de touche + modificateurs) se lit sans
///   changement ;
/// - modificateurs seuls illisibles (un seul modificateur, ⇧ seul, masque 0)
///   : défaut ⌃⌥Espace, jamais un raccourci inutilisable.
///
/// Masques Carbon : cmd 256, shift 512, option 2048, control 4096 ;
/// ⌘⌥ = 2304.
void main() {
  final File prefs = File('${appDataDirectory()}/prefs.json');
  const DictationShortcut cmdOption = DictationShortcut(
    keyCode: null,
    modifiers: 256 | 2048,
  );

  setUp(() {
    expect(prefs.path, startsWith(Directory.systemTemp.path));
    if (prefs.existsSync()) prefs.deleteSync();
  });

  Map<String, dynamic> stored() =>
      jsonDecode(prefs.readAsStringSync()) as Map<String, dynamic>;

  void writeByHand(Map<String, Object> json) {
    prefs.parent.createSync(recursive: true);
    prefs.writeAsStringSync(jsonEncode(json));
  }

  test('un prefs.json d avant (code de touche + modificateurs) se lit sans '
      'changement', () async {
    writeByHand(<String, Object>{
      'dictation_enabled': true,
      'dictation_key_code': 2,
      'dictation_modifiers': 4608,
      'dictation_output_mode': 'clipboard',
    });

    final DictationSettings s = await DictationPreferences().load();

    expect(s.shortcut.keyCode, 2);
    expect(s.shortcut.modifiers, 4608);
    expect(s.outputMode, DictationOutputMode.clipboard);
  });

  test('⌘⌥ seuls : stockés en modificateurs sans code de touche', () async {
    await DictationPreferences().save(
      const DictationSettings(shortcut: cmdOption),
    );

    expect(stored(), containsPair('dictation_modifiers', 2304));
    expect(stored().containsKey('dictation_key_code'), isFalse);
  });

  test('⌘⌥ seuls : relus à l identique par une autre instance', () async {
    await DictationPreferences().save(
      const DictationSettings(
        enabled: false,
        shortcut: cmdOption,
        outputMode: DictationOutputMode.clipboard,
      ),
    );

    final DictationSettings s = await DictationPreferences().load();

    expect(s.enabled, isFalse);
    expect(s.shortcut.keyCode, isNull);
    expect(s.shortcut.modifiers, 2304);
    expect(s.outputMode, DictationOutputMode.clipboard);
  });

  test('d un raccourci à touche vers ⌘⌥ seuls : l ancien code de touche ne '
      'reste pas', () async {
    await DictationPreferences().save(
      const DictationSettings(
        shortcut: DictationShortcut(keyCode: 49, modifiers: 6144),
      ),
    );
    await DictationPreferences().save(
      const DictationSettings(shortcut: cmdOption),
    );

    final DictationSettings s = await DictationPreferences().load();

    expect(s.shortcut.keyCode, isNull);
    expect(s.shortcut.modifiers, 2304);
    expect(stored().containsKey('dictation_key_code'), isFalse);
  });

  test('de ⌘⌥ seuls vers un raccourci à touche : relu avec sa touche', () async {
    await DictationPreferences().save(
      const DictationSettings(shortcut: cmdOption),
    );
    await DictationPreferences().save(
      const DictationSettings(
        shortcut: DictationShortcut(keyCode: 2, modifiers: 2304),
      ),
    );

    final DictationSettings s = await DictationPreferences().load();

    expect(s.shortcut.keyCode, 2);
    expect(s.shortcut.modifiers, 2304);
  });

  test('modificateurs seuls écrits à la main dans prefs.json : lus comme '
      'tels', () async {
    writeByHand(<String, Object>{'dictation_modifiers': 4096 | 512});

    final DictationSettings s = await DictationPreferences().load();

    expect(s.shortcut.keyCode, isNull);
    expect(s.shortcut.modifiers, 4608);
  });

  for (final ({String name, int modifiers}) bad
      in <({String name, int modifiers})>[
        (name: '⌘ seul', modifiers: 256),
        (name: '⇧ seul', modifiers: 512),
        (name: 'aucun modificateur', modifiers: 0),
      ]) {
    test('modificateurs seuls invalides sur disque (${bad.name}) : défaut '
        '⌃⌥Espace', () async {
      writeByHand(<String, Object>{'dictation_modifiers': bad.modifiers});

      final DictationSettings s = await DictationPreferences().load();

      expect(s.shortcut.keyCode, 49);
      expect(s.shortcut.modifiers, 4096 | 2048);
    });
  }
}
