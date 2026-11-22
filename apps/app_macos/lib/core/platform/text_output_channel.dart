import 'package:flutter/services.dart';

/// Dart wrapper autour du plugin Swift TextOutputPlugin : presse-papiers et
/// ⌘V synthétique pour la sortie de la dictée.
class TextOutputChannel {
  static const MethodChannel _method = MethodChannel(
    'com.icitranscript/text_output',
  );

  /// Permission Accessibilité (requise pour coller), sans demande système.
  /// Faux si inconnue.
  Future<bool> isAccessibilityTrusted() async {
    try {
      return await _method.invokeMethod<bool>('isAccessibilityTrusted') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Remplace le presse-papiers par [text].
  Future<void> copy(String text) =>
      _method.invokeMethod<void>('copy', <String, String>{'text': text});

  /// Garde côté Swift une copie de tout le presse-papiers.
  Future<void> saveClipboard() => _method.invokeMethod<void>('saveClipboard');

  /// Remet la copie faite par [saveClipboard].
  Future<void> restoreClipboard() =>
      _method.invokeMethod<void>('restoreClipboard');

  /// ⌘V vers l'app au premier plan. Rend la main une fois les événements
  /// postés, pas consommés : attendre avant [restoreClipboard]. Lève une
  /// PlatformException en cas d'échec.
  Future<void> paste() => _method.invokeMethod<void>('paste');
}
