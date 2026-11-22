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
/// Chaque opération passe dans une file par fichier, dans l'ordre d'appel :
/// deux écritures rapprochées ne s'écrasent pas, et une lecture voit les
/// écritures demandées avant elle. Écriture atomique (fichier temporaire puis
/// renommage) : un lecteur ne voit jamais un fichier à moitié écrit.
// ponytail: verrou dans le processus seulement ; un 2e processus qui écrit
// prefs.json (aucun aujourd'hui) demanderait un verrou de fichier.
class PrefsStore {
  /// Crée le magasin sur [path] (défaut : prefs.json du dossier de données).
  PrefsStore([String? path])
    : path = path ?? '${appDataDirectory()}/prefs.json';

  /// Chemin du fichier.
  final String path;

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};

  /// Lance [op] après toutes les opérations déjà demandées sur ce fichier.
  Future<T> _locked<T>(T Function() op) {
    final Future<T> result = (_queues[path] ?? Future<void>.value()).then(
      (_) => op(),
    );
    _queues[path] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Toutes les valeurs ; vide si le fichier manque ou n'est pas un objet
  /// JSON valide.
  Future<Map<String, Object?>> read() => _locked(_readSync);

  /// Fusionne [values] dans le fichier ; une valeur null retire la clé.
  Future<void> update(Map<String, Object?> values) => _locked(() {
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

  // Synchrone : le travail sur le fichier tient dans un seul tour de la file.
  Map<String, Object?> _readSync() {
    try {
      final Object? json = jsonDecode(File(path).readAsStringSync());
      return json is Map<String, dynamic> ? json : <String, Object?>{};
    } on Object {
      return <String, Object?>{};
    }
  }
}

/// [json]\[key] si c'est un [T], sinon null (type inattendu = absent).
T? prefValue<T>(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  return value is T ? value : null;
}
