import 'package:flutter/services.dart';

/// Événement du raccourci global de la dictée.
///
/// [aborted] : une autre touche ou un clic pendant que les modificateurs
/// d'un raccourci « modificateurs seuls » sont tenus (raccourci d'une autre
/// app) ; aucun [released] ne suit pour cet appui.
///
/// [tapped] : appui bref propre d'un raccourci « modificateurs seuls »
/// (relâché avant le seuil, rien d'autre) ; pour ces raccourcis [pressed]
/// n'arrive qu'au seuil, l'appui maintenu étant alors confirmé.
enum ShortcutEvent { pressed, released, cancel, aborted, tapped }

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
  /// Un seul abonnement plateforme partagé (le plugin n'a qu'un récepteur),
  /// ouvert seulement à la première écoute.
  late final Stream<ShortcutEvent> events = _events
      .receiveBroadcastStream()
      .map(
        (Object? e) => switch (e) {
          {'type': 'pressed'} => ShortcutEvent.pressed,
          {'type': 'released'} => ShortcutEvent.released,
          {'type': 'cancel'} => ShortcutEvent.cancel,
          {'type': 'aborted'} => ShortcutEvent.aborted,
          {'type': 'tapped'} => ShortcutEvent.tapped,
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

  /// Raccourci « modificateurs seuls » (masque Carbon, ⌘⌥ = 2304), à la
  /// place du précédent. Faux si refusé (Accessibilité absente) ou plugin
  /// absent.
  /// Le plugin ne dit rien pendant [holdThreshold] : un accord suivi d'une
  /// autre touche ou d'un clic n'est jamais le nôtre.
  Future<bool> registerModifiers({
    required int modifiers,
    Duration? holdThreshold,
  }) async {
    try {
      await _method.invokeMethod<void>('registerModifiers', <String, int>{
        'modifiers': modifiers,
        if (holdThreshold != null) 'holdMs': holdThreshold.inMilliseconds,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Caractères de la touche [keyCode] dans la disposition de clavier
  /// courante, sans modificateur ; null si inconnus ou plugin absent.
  Future<String?> keyLabel(int keyCode) async {
    try {
      return await _method.invokeMethod<String>('keyLabel', <String, int>{
        'keyCode': keyCode,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Retire le raccourci (et la capture d'Échap).
  Future<void> unregister() => _method.invokeMethod<void>('unregister');

  /// Capture Échap seulement pendant une dictée.
  Future<void> setCancelKeyEnabled(bool enabled) => _method.invokeMethod<void>(
    'setCancelKeyEnabled',
    <String, bool>{'enabled': enabled},
  );
}
