import 'package:flutter/services.dart';

/// Événement du raccourci global de la dictée.
enum ShortcutEvent { pressed, released, cancel }

/// Dart wrapper autour du plugin Swift GlobalShortcutPlugin (raccourci
/// global Carbon, appui maintenu pour dicter, Échap pour annuler).
class GlobalShortcutChannel {
  static const MethodChannel _method = MethodChannel(
    'com.icitranscript/global_shortcut',
  );
  static const EventChannel _events = EventChannel(
    'com.icitranscript/global_shortcut_events',
  );

  /// Appuis, relâchements et annulations ; les types inconnus sont ignorés.
  /// Écoute le plugin seulement à l'abonnement.
  Stream<ShortcutEvent> get events => _events
      .receiveBroadcastStream()
      .map(
        (Object? e) => switch (e) {
          {'type': 'pressed'} => ShortcutEvent.pressed,
          {'type': 'released'} => ShortcutEvent.released,
          {'type': 'cancel'} => ShortcutEvent.cancel,
          _ => null,
        },
      )
      .where((ShortcutEvent? e) => e != null)
      .cast<ShortcutEvent>();

  /// Enregistre le raccourci (remplace le précédent). Faux s'il est déjà
  /// pris ou si le plugin est absent.
  Future<bool> register({required int keyCode, required int modifiers}) async {
    try {
      await _method.invokeMethod<void>('register', <String, int>{
        'keyCode': keyCode,
        'modifiers': modifiers,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Retire le raccourci (et la capture d'Échap).
  Future<void> unregister() => _method.invokeMethod<void>('unregister');

  /// Capture Échap seulement pendant une dictée.
  Future<void> setCancelKeyEnabled(bool enabled) => _method
      .invokeMethod<void>('setCancelKeyEnabled', <String, bool>{
        'enabled': enabled,
      });
}
