import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';

/// Réglages de la dictée (T2) : par le `PrefsStore` partagé, dans prefs.json, à côté des autres réglages,
/// jamais seulement en mémoire. Raccourci stocké en code de touche macOS +
/// masque de modificateurs Carbon (⌃⌥Espace = 49 / 4096 | 2048 = 6144).
///
/// Défauts choisis : dictée activée (coût : le modèle est chargé à chaque
/// lancement), ⌃⌥Espace (⌥Espace tape une espace insécable sur
/// clavier français), mode collage (repli presse-papiers sans
/// Accessibilité).
void main() {
  final File prefs = File('${appDataDirectory()}/prefs.json');

  setUp(() {
    expect(prefs.path, startsWith(Directory.systemTemp.path));
    if (prefs.existsSync()) prefs.deleteSync();
  });

  Map<String, dynamic> stored() =>
      jsonDecode(prefs.readAsStringSync()) as Map<String, dynamic>;

  test('sans prefs.json : défauts (activée, ⌃⌥Espace, collage)', () async {
    final DictationSettings s = await DictationPreferences().load();

    expect(s.enabled, isTrue);
    expect(s.shortcut.keyCode, 49);
    expect(s.shortcut.modifiers, 4096 | 2048);
    expect(s.outputMode, DictationOutputMode.paste);
  });

  test(
    'enregistrés puis relus par une autre instance : mêmes valeurs',
    () async {
      await DictationPreferences().save(
        const DictationSettings(
          enabled: false,
          shortcut: DictationShortcut(keyCode: 2, modifiers: 4608),
          outputMode: DictationOutputMode.clipboard,
        ),
      );

      final DictationSettings s = await DictationPreferences().load();

      expect(s.enabled, isFalse);
      expect(s.shortcut.keyCode, 2);
      expect(s.shortcut.modifiers, 4608);
      expect(s.outputMode, DictationOutputMode.clipboard);
    },
  );

  test('stockés dans prefs.json en code de touche + modificateurs', () async {
    await DictationPreferences().save(
      const DictationSettings(
        shortcut: DictationShortcut(keyCode: 2, modifiers: 4608),
        outputMode: DictationOutputMode.clipboard,
      ),
    );

    expect(stored(), containsPair('dictation_enabled', true));
    expect(stored(), containsPair('dictation_key_code', 2));
    expect(stored(), containsPair('dictation_modifiers', 4608));
    expect(stored(), containsPair('dictation_output_mode', 'clipboard'));
  });

  test('les autres réglages de prefs.json sont gardés', () async {
    prefs.parent.createSync(recursive: true);
    prefs.writeAsStringSync(
      jsonEncode(<String, Object>{
        'selected_mic_id': 'mic-2',
        'system_audio_enabled': false,
      }),
    );

    await DictationPreferences().save(const DictationSettings());

    expect(stored(), containsPair('selected_mic_id', 'mic-2'));
    expect(stored(), containsPair('system_audio_enabled', false));
    expect(stored(), containsPair('dictation_key_code', 49));
    expect(stored(), containsPair('dictation_modifiers', 6144));
  });

  test('prefs.json illisible : défauts, sans lever', () async {
    prefs.parent.createSync(recursive: true);
    prefs.writeAsStringSync('{pas du json');

    final DictationSettings s = await DictationPreferences().load();

    expect(s.enabled, isTrue);
    expect(s.shortcut.keyCode, 49);
    expect(s.outputMode, DictationOutputMode.paste);
  });

  test(
    'passent par le PrefsStore partagé (même fichier, mêmes clés)',
    () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'oats_prefs_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final PrefsStore store = PrefsStore('${dir.path}/prefs.json');
      await store.update(<String, Object?>{'llm_active': 'ollama'});

      await DictationPreferences(store).save(
        const DictationSettings(outputMode: DictationOutputMode.clipboard),
      );

      final Map<String, Object?> json = await store.read();
      expect(json, containsPair('llm_active', 'ollama'));
      expect(json, containsPair('dictation_output_mode', 'clipboard'));
      expect(
        (await DictationPreferences(store).load()).outputMode,
        DictationOutputMode.clipboard,
      );
    },
  );
}
