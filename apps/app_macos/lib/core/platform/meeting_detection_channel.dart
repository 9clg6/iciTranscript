import 'dart:async';

import 'package:flutter/services.dart';

/// Surveillance des processus qui tiennent le micro
/// (`MeetingDetectionPlugin.swift`, Core Audio, macOS 14+).
///
/// Canal `com.icitranscript/meeting_detection` : `start` → bool (false sous
/// macOS 14), `stop` ; Swift envoie `micUsers {bundleIds}` à chaque
/// changement (Oats exclu).
class MeetingDetectionChannel {
  /// Crée le canal.
  const MeetingDetectionChannel();

  static const MethodChannel _channel = MethodChannel(
    'com.icitranscript/meeting_detection',
  );

  static final StreamController<Set<String>> _micUsers =
      StreamController<Set<String>>.broadcast(onListen: _listenToSwift);

  static void _listenToSwift() => _channel.setMethodCallHandler((
    MethodCall call,
  ) async {
    if (call.method != 'micUsers') return;
    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    _micUsers.add(
      (args['bundleIds'] as List<Object?>? ?? <Object?>[])
          .whereType<String>()
          .toSet(),
    );
  });

  /// Instantanés des autres processus qui tiennent l'entrée audio.
  Stream<Set<String>> get micUsers => _micUsers.stream;

  /// Lance la surveillance ; false si non prise en charge (macOS < 14 ou
  /// plugin absent).
  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Arrête la surveillance.
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
