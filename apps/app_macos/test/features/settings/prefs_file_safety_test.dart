import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';

import '../../helpers/settings_fakes.dart';

/// prefs.json : écritures sûres (besoin 8 de la tranche « Réglages IA et
/// persistance »).
///
/// - Deux écritures en même temps ne perdent jamais la clé de l'autre.
/// - Un fichier corrompu ou tronqué redonne les valeurs par défaut, sans
///   plantage ; un fichier JSON valide garde ses clés inconnues (écrites par
///   une autre partie de l'app, ou une version plus récente).
///
/// Passe par le vrai SettingsViewModel (seul écrivain sur main) ; prefs.json
/// est celui du dossier temporaire des tests.
void main() {
  setUp(resetPrefs);

  List<Override> overrides() => <Override>[
    audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
    apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
  ];

  /// Démarre l'app (un conteneur = un lancement) et attend la fin du
  /// chargement des réglages.
  Future<ProviderContainer> launch() async {
    final ProviderContainer c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c.read(settingsViewModelProvider);
    await eventually(
      () => expect(c.read(settingsViewModelProvider).storagePath, isNotEmpty),
    );
    return c;
  }

  SettingsViewModel vmOf(ProviderContainer c) =>
      c.read(settingsViewModelProvider.notifier);

  group('deux écritures en même temps', () {
    test('micro et audio système changés ensemble : les deux survivent au '
        'redémarrage', () async {
      final ProviderContainer c = await launch();

      // Lancées sans attendre l'une l'autre, comme deux clics rapprochés.
      await Future.wait(<Future<void>>[
        vmOf(c).updateMic('mic-2'),
        vmOf(c).toggleSystemAudio(),
      ]);

      final Map<String, dynamic> prefs = readPrefs();
      expect(prefs['selected_mic_id'], 'mic-2');
      expect(prefs['system_audio_enabled'], isFalse);

      final ProviderContainer again = await launch();
      final SettingsState s = again.read(settingsViewModelProvider);
      expect(s.selectedMicId, 'mic-2');
      expect(s.systemAudioEnabled, isFalse);
    });

    test('vingt allers-retours rapprochés : aucune valeur perdue', () async {
      final ProviderContainer c = await launch();
      bool systemAudio = true;

      for (int i = 0; i < 20; i++) {
        final String mic = i.isEven ? 'mic-1' : 'mic-2';
        systemAudio = !systemAudio;
        await Future.wait(<Future<void>>[
          vmOf(c).updateMic(mic),
          vmOf(c).toggleSystemAudio(),
        ]);
        final Map<String, dynamic> prefs = readPrefs();
        expect(prefs['selected_mic_id'], mic, reason: 'tour $i');
        expect(prefs['system_audio_enabled'], systemAudio, reason: 'tour $i');
      }
    });

    test('un lecteur ne voit jamais un fichier à moitié écrit', () async {
      // Grosse valeur inconnue : l'écriture prend du temps, la fenêtre où un
      // fichier tronqué serait visible est large.
      prefsFile.parent.createSync(recursive: true);
      prefsFile.writeAsStringSync(
        jsonEncode(<String, Object?>{'other_writer_blob': 'x' * (4 << 20)}),
      );
      final ProviderContainer c = await launch();

      final List<String> broken = <String>[];
      bool writing = true;
      final Future<void> reader = () async {
        while (writing) {
          try {
            final String raw = await prefsFile.readAsString();
            final Object? json = jsonDecode(raw);
            if (json is! Map) broken.add('pas un objet');
          } on Object catch (e) {
            broken.add(e.runtimeType.toString());
          }
          await Future<void>.delayed(Duration.zero);
        }
      }();

      for (int i = 0; i < 15; i++) {
        await vmOf(c).updateMic(i.isEven ? 'mic-1' : 'mic-2');
      }
      writing = false;
      await reader;

      expect(broken, isEmpty, reason: 'lectures invalides pendant l\'écriture');
      expect(readPrefs()['other_writer_blob'], hasLength(4 << 20));
    });
  });

  group('fichier abîmé', () {
    const Map<String, String> damaged = <String, String>{
      'pas du JSON': 'not json {{',
      'tronqué au milieu': '{"selected_mic_id": "mic-2", "system_au',
      'vide': '',
      'JSON valide mais tableau': '[1, 2]',
      'JSON valide mais null': 'null',
    };

    damaged.forEach((String name, String content) {
      test('$name : lancement sans plantage, valeurs par défaut, puis '
          'écriture d\'un fichier valide', () async {
        prefsFile.parent.createSync(recursive: true);
        prefsFile.writeAsStringSync(content);

        final ProviderContainer c = await launch();
        final SettingsState s = c.read(settingsViewModelProvider);
        expect(s.systemAudioEnabled, isTrue, reason: 'défaut');
        expect(s.selectedMicId, isNull, reason: 'défaut');

        await vmOf(c).updateMic('mic-1');

        expect(readPrefs()['selected_mic_id'], 'mic-1');
      });
    });
  });

  group('clés inconnues', () {
    test('un fichier valide garde les clés qu\'il ne connaît pas après une '
        'écriture', () async {
      prefsFile.parent.createSync(recursive: true);
      prefsFile.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'dictation_shortcut': 'cmd+shift+d',
          'future_section': <String, Object?>{'a': 1, 'b': <int>[1, 2]},
          'system_audio_enabled': true,
        }),
      );

      final ProviderContainer c = await launch();
      await vmOf(c).toggleSystemAudio();

      final Map<String, dynamic> prefs = readPrefs();
      expect(prefs['system_audio_enabled'], isFalse);
      expect(prefs['dictation_shortcut'], 'cmd+shift+d');
      expect(prefs['future_section'], <String, Object?>{
        'a': 1,
        'b': <int>[1, 2],
      });
    });

    test('une valeur d\'un type inattendu ne plante pas le lancement et '
        'n\'efface pas les autres clés', () async {
      prefsFile.parent.createSync(recursive: true);
      prefsFile.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'system_audio_enabled': 'oui',
          'dictation_shortcut': 'cmd+shift+d',
        }),
      );

      final ProviderContainer c = await launch();
      expect(c.read(settingsViewModelProvider).systemAudioEnabled, isTrue);
      await vmOf(c).updateMic('mic-2');

      final Map<String, dynamic> prefs = readPrefs();
      expect(prefs['selected_mic_id'], 'mic-2');
      expect(prefs['dictation_shortcut'], 'cmd+shift+d');
    });
  });
}
