import 'package:flutter/services.dart';

/// Sélecteur de fichiers natif (NSOpenPanel, côté Swift).
///
/// Canal `com.icitranscript/file_picker`, méthode `pickFiles`
/// `{extensions}` (sans point, minuscules) → chemins absolus, null si
/// l'utilisateur annule.
class FilePickerChannel {
  /// Crée le canal.
  const FilePickerChannel();

  static const MethodChannel _channel = MethodChannel(
    'com.icitranscript/file_picker',
  );

  /// Chemins choisis parmi les fichiers d'[extensions] ; vide si annulé.
  Future<List<String>> pickFiles({required List<String> extensions}) async {
    final List<String>? paths = await _channel.invokeListMethod<String>(
      'pickFiles',
      <String, Object?>{'extensions': extensions},
    );
    return paths ?? const <String>[];
  }
}
