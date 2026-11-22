import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/transcription_model_cache.dart';
import 'package:ici_transcript/core/platform/voxmlx_server.dart';

/// Revue PR #19, point 3 : savoir, sans rien télécharger, si le modèle de
/// transcription (plusieurs Go) est déjà dans le cache Hugging Face.
///
/// API supposée (lib/core/platform/transcription_model_cache.dart) :
/// - `const String transcriptionModelId` : le modèle passé à voxmlx-serve ;
/// - `bool isTranscriptionModelCached(Map<String, String> environment)` :
///   cache = `HF_HUB_CACHE`, sinon `HF_HOME/hub`, sinon
///   `HOME/.cache/huggingface/hub` ; vrai si
///   `models--<org>--<nom>/snapshots/` contient un instantané non vide.
/// Aucune vérification équivalente n'existait pour les réunions.
void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('oats_hf_home_');
  });
  tearDown(() => home.deleteSync(recursive: true));

  String repoDir(String hub) =>
      '$hub/models--${transcriptionModelId.replaceAll('/', '--')}';

  void snapshot(String hub, {bool withFile = true}) {
    final Directory snap = Directory('${repoDir(hub)}/snapshots/abc123')
      ..createSync(recursive: true);
    if (withFile) File('${snap.path}/config.json').writeAsStringSync('{}');
  }

  test('le modèle vérifié est celui que lance le serveur', () {
    expect(voxmlxArgs(), contains(transcriptionModelId));
  });

  test('cache vide : absent', () {
    expect(
      isTranscriptionModelCached(<String, String>{'HOME': home.path}),
      isFalse,
    );
  });

  test('instantané présent sous HOME/.cache/huggingface/hub : présent', () {
    snapshot('${home.path}/.cache/huggingface/hub');

    expect(
      isTranscriptionModelCached(<String, String>{'HOME': home.path}),
      isTrue,
    );
  });

  test('dossier d instantané vide (téléchargement interrompu) : absent', () {
    snapshot('${home.path}/.cache/huggingface/hub', withFile: false);

    expect(
      isTranscriptionModelCached(<String, String>{'HOME': home.path}),
      isFalse,
    );
  });

  test('HF_HOME puis HF_HUB_CACHE priment sur HOME', () {
    snapshot('${home.path}/hfhome/hub');
    expect(
      isTranscriptionModelCached(<String, String>{
        'HOME': '/nulle-part',
        'HF_HOME': '${home.path}/hfhome',
      }),
      isTrue,
    );

    snapshot('${home.path}/hubcache');
    expect(
      isTranscriptionModelCached(<String, String>{
        'HOME': '/nulle-part',
        'HF_HOME': '/nulle-part',
        'HF_HUB_CACHE': '${home.path}/hubcache',
      }),
      isTrue,
    );
  });
}
