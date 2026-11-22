import 'dart:io';

/// Durée de conservation des WAV de session, toujours enregistrés
/// (~230 Mo par heure de réunion, micro + son du Mac).
///
/// Sans appelant pour l'instant : jamais lancée automatiquement (au premier
/// lancement, elle effacerait des mois d'enregistrements). Une tranche
/// ultérieure la déclenche depuis un geste explicite de l'utilisateur.
abstract final class RecordingRetention {
  /// Seule constante de la durée de conservation.
  static const Duration maxAge = Duration(days: 14);

  static final RegExp _recording = RegExp(r'^(.+)_(mic|system)\.wav$');

  /// Chemins à supprimer parmi [files] : WAV de session plus vieux que
  /// [maxAge], sauf ceux d'une session de [activeSessionIds].
  static List<String> expired(
    List<({String path, DateTime modified})> files, {
    required Set<String> activeSessionIds,
    required DateTime now,
  }) => <String>[
    for (final ({String path, DateTime modified}) file in files)
      if (_recording.firstMatch(file.path.split('/').last)
          case final RegExpMatch match
          when !activeSessionIds.contains(match.group(1)) &&
              now.difference(file.modified) > maxAge)
        file.path,
  ];

  /// Supprime les WAV expirés de [directory]. Un dossier absent ou un
  /// fichier illisible ne fait jamais échouer l'appelant.
  static Future<void> purge(
    String directory, {
    required Set<String> activeSessionIds,
    required DateTime now,
  }) async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) return;
    final List<({String path, DateTime modified})> files =
        <({String path, DateTime modified})>[
          for (final FileSystemEntity entry in dir.listSync())
            if (entry is File)
              (path: entry.path, modified: entry.lastModifiedSync()),
        ];
    for (final String path in expired(
      files,
      activeSessionIds: activeSessionIds,
      now: now,
    )) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Fichier déjà parti ou verrouillé : réessayé au prochain lancement.
      }
    }
  }
}
