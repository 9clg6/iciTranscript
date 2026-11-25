import 'dart:io';

/// Audio d'une session : filet de sécurité TEMPORAIRE. Oats ne garde aucun
/// audio de réunion, seulement les transcriptions : les fichiers
/// `<id>_mic.wav`, `<id>_system.wav`, `<id>_mic.nodictation.wav` et
/// `<id>_dictations.json` sont supprimés dès que le traitement de la note
/// est fini, quelle qu'en soit l'issue (un repère non récupéré reste).
///
/// Une note en cours de traitement porte `<id>_processing` (écrit au début
/// de l'arrêt) : un lancement qui la retrouve finit son traitement puis
/// supprime. Rien d'autre n'est supprimé au lancement.
final class SessionAudio {
  /// Cree une instance de [SessionAudio].
  const SessionAudio(this.recordingsDir);

  /// Dossier des enregistrements.
  final String recordingsDir;

  File _marker(String id) => File('$recordingsDir/${id}_processing');

  /// Note le traitement de [sessionId] en cours (durable).
  // Synchrone : l'arrêt ne doit pas céder la main avant de commencer.
  void markProcessing(String sessionId) {
    Directory(recordingsDir).createSync(recursive: true);
    _marker(sessionId).writeAsStringSync('', flush: true);
  }

  /// Sessions dont le traitement n'a pas fini (app arrêtée en route).
  List<String> processing() {
    final Directory dir = Directory(recordingsDir);
    if (!dir.existsSync()) return const <String>[];
    return <String>[
      for (final FileSystemEntity e in dir.listSync())
        if (e is File && e.path.endsWith('_processing'))
          e.uri.pathSegments.last.replaceFirst(RegExp(r'_processing$'), ''),
    ];
  }

  /// Supprime tout fichier `<sessionId>_*` (repère de traitement compris).
  /// Idempotent ; ne lève jamais.
  Future<void> discard(String sessionId) async {
    final Directory dir = Directory(recordingsDir);
    if (!dir.existsSync()) return;
    for (final FileSystemEntity e in dir.listSync()) {
      if (e is! File || !e.uri.pathSegments.last.startsWith('${sessionId}_')) {
        continue;
      }
      try {
        await e.delete();
      } catch (_) {}
    }
  }
}
