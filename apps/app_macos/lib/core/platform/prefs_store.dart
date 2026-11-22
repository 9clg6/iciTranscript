import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// prefs.json : seul point de lecture et d'écriture des réglages de l'app.
///
/// Valeurs JSON génériques par clé, pour que chaque partie de l'app (Réglages,
/// direct, dictée…) range les siennes sans connaître les autres. Les clés
/// inconnues sont gardées ; un fichier abîmé se lit comme vide.
///
/// Chaque opération lit, fusionne et écrit d'un seul bloc synchrone : dans
/// l'isolat, rien ne peut s'intercaler (c'est le verrou), et les appels non
/// attendus s'appliquent dans l'ordre d'appel. Écriture atomique (fichier
/// temporaire puis renommage) : un lecteur ne voit jamais un fichier à
/// moitié écrit.
// ponytail: E/S synchrones sur un fichier de quelques Ko ; un autre isolat ou
// processus qui écrirait prefs.json (aucun aujourd'hui) demanderait un verrou
// de fichier.
class PrefsStore {
  /// Crée le magasin sur [path] (défaut : prefs.json du dossier de données).
  PrefsStore([String? path])
    : path = path ?? '${appDataDirectory()}/prefs.json';

  /// Chemin du fichier.
  final String path;

  /// Toutes les valeurs ; vide si le fichier manque ou n'est pas un objet
  /// JSON valide.
  Future<Map<String, Object?>> read() =>
      Future<Map<String, Object?>>.sync(_readSync);

  /// Fusionne [values] dans le fichier ; une valeur null retire la clé.
  Future<void> update(Map<String, Object?> values) => Future<void>.sync(() {
    final Map<String, Object?> json = _readSync();
    values.forEach((String key, Object? value) {
      if (value == null) {
        json.remove(key);
      } else {
        json[key] = value;
      }
    });
    final File file = File(path);
    file.parent.createSync(recursive: true);
    final File tmp = File('$path.tmp');
    tmp.writeAsStringSync(jsonEncode(json), flush: true);
    tmp.renameSync(path);
  });

  Map<String, Object?> _readSync() {
    try {
      final Object? json = jsonDecode(File(path).readAsStringSync());
      return json is Map<String, dynamic> ? json : <String, Object?>{};
    } on Object {
      return <String, Object?>{};
    }
  }
}

/// Micro choisi dans Réglages (réunions et dictée).
const String selectedMicPrefKey = 'selected_mic_id';

/// [json]\[key] si c'est un [T], sinon null (type inattendu = absent).
T? prefValue<T>(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  return value is T ? value : null;
}
