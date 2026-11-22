import 'dart:io';

/// Modèle passé à voxmlx-serve (un seul endroit : la commande du serveur le
/// reprend).
const String transcriptionModelId =
    'T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit';

/// Vrai si le modèle de transcription (plusieurs Go) est déjà dans le cache
/// Hugging Face : `HF_HUB_CACHE`, sinon `HF_HOME/hub`, sinon
/// `HOME/.cache/huggingface/hub`, avec un instantané non vide. Ne
/// télécharge rien.
// ponytail: un instantané non vide suffit ; un téléchargement coupé après
// les premiers fichiers passe pour complet (le serveur le reprendra).
bool isTranscriptionModelCached(Map<String, String> environment) {
  final String? hfHome = environment['HF_HOME'];
  final String hub =
      environment['HF_HUB_CACHE'] ??
      (hfHome != null
          ? '$hfHome/hub'
          : '${environment['HOME'] ?? ''}/.cache/huggingface/hub');
  final Directory snapshots = Directory(
    '$hub/models--${transcriptionModelId.replaceAll('/', '--')}/snapshots',
  );
  try {
    return snapshots.listSync().whereType<Directory>().any(
      (Directory d) => d.listSync().isNotEmpty,
    );
  } on FileSystemException {
    return false;
  }
}

/// Vérification de l'app. Sous `flutter test`, le modèle est supposé là
/// (jamais le vrai cache de l'utilisateur) : les specs qui veulent l'absence
/// le disent par une surcharge.
bool transcriptionModelCachedNow() =>
    Platform.environment.containsKey('FLUTTER_TEST') ||
    isTranscriptionModelCached(Platform.environment);
