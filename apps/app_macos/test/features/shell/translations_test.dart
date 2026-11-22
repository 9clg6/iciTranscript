import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

/// Les textes du shell, de l'accueil et du détail viennent de fr.json.
void main() {
  group('fr.json : valeurs imposées par le besoin', () {
    const Map<String, String> exact = <String, String>{
      'app.name': 'Oats',
      // Repère d'un lancement de dev (dossier de données isolé).
      'app.dev_data': 'données de dev',
      'nav.home': 'Accueil',
      'nav.documents': 'Documents',
      'nav.coach': 'Coach anglais',
      'nav.settings': 'Réglages',
      'common.label.today': "Aujourd'hui",
      'common.label.yesterday': 'Hier',
      'common.action.back': 'Retour',
      'common.action.close': 'Fermer',
      'home.upcoming.title': 'À venir',
      // L'app vouvoie : la source micro s'appelle « Vous ».
      'history.detail.speaker_me': 'Vous',
      // Arrêt : attente du rattrapage de la transcription (tour 5 bis).
      'transcription.live.finalising': 'Finalisation de la transcription…',
      'transcription.live.finalising_remaining': '~{} s',
      'transcription.live.skip_finalising': 'Passer',
    };
    exact.forEach((String key, String value) {
      test('$key = « $value »', () => expect(frValue(key), value));
    });
  });

  group('fr.json : clés présentes et non vides', () {
    const List<String> keys = <String>[
      'home.empty',
      'home.new_note',
      'home.upcoming.no_calendar',
      'history.detail.copy',
      'history.detail.export_markdown',
      'history.detail.summarize',
      'history.detail.english_coach',
      'history.detail.delete',
      'history.detail.delete_confirm',
      'common.action.cancel',
      'common.action.delete',
      'common.error.generic',
      'transcription.live.speaker_me',
      'transcription.live.speaker_system',
      'llm.configure_model',
      'settings.local_model.install',
      'settings.local_model.ready',
      'ollama.step_model',
      'ollama.error',
      'common.action.retry',
    ];
    for (final String key in keys) {
      test(key, () {
        final Object? v = frValue(key);
        expect(v, isA<String>(), reason: key);
        expect((v! as String).trim(), isNotEmpty, reason: key);
      });
    }

    test('history.detail.speaker prend le numéro en argument', () {
      expect(frValue('history.detail.speaker'), contains('{}'));
    });

    test('home.upcoming.attendees existe (texte ou pluriel)', () {
      final Object? v = frValue('home.upcoming.attendees');
      expect(v is String || v is Map<String, dynamic>, isTrue);
    });
  });

  test('aucun « Retour » ni « Fermer » écrit en dur dans lib/', () {
    final RegExp literal = RegExp(r'''['"](Retour|Fermer)['"]''');
    final List<String> offenders = <String>[
      for (final FileSystemEntity f in Directory(
        'lib',
      ).listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.endsWith('.gr.dart') &&
            literal.hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
