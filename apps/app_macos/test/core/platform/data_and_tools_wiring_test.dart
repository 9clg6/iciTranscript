import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Les enregistrements sont des données de l'utilisateur : en debug ils vont
/// dans Oats-dev, jamais dans le vrai dossier. Les poids Nemotron sont un
/// cache d'outil : partagés avec le vrai dossier pour ne pas les
/// retélécharger. Sous flutter test les deux dossiers sont distincts, ce qui
/// permet de vérifier où chaque chemin est rangé.
void main() {
  bool isUnder(String path, String dir) => path.startsWith('$dir/');

  test('les enregistrements de session vivent dans le dossier de données', () {
    expect(
      isUnder(LiveTranscriptionService.recordingsDir, appDataDirectory()),
      isTrue,
      reason: LiveTranscriptionService.recordingsDir,
    );
    expect(
      isUnder(LiveTranscriptionService.recordingsDir, toolsDirectory()),
      isFalse,
    );
  });

  test('la passe post-session lit les enregistrements au même endroit', () {
    expect(
      DiarizationService().recordingsDir,
      LiveTranscriptionService.recordingsDir,
    );
  });

  test('les poids Nemotron vivent dans le dossier des outils', () {
    expect(
      isUnder(DiarizationService.modelCacheDir, toolsDirectory()),
      isTrue,
      reason: DiarizationService.modelCacheDir,
    );
    expect(
      isUnder(DiarizationService.modelCacheDir, appDataDirectory()),
      isFalse,
    );
  });
}
