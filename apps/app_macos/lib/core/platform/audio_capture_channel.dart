import 'dart:async';

import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter/services.dart';

/// Dart wrapper autour du plugin Swift AudioCapturePlugin.
///
/// Expose la capture micro et audio systeme comme un [Stream<AudioChunk>].
class AudioCaptureChannel {
  /// Cree une instance de [AudioCaptureChannel].
  AudioCaptureChannel()
    : _methodChannel = const MethodChannel('com.icitranscript/audio_control'),
      _eventChannel = const EventChannel('com.icitranscript/audio_stream');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  StreamSubscription<dynamic>? _eventSubscription;
  final StreamController<AudioChunk> _audioController =
      StreamController<AudioChunk>.broadcast();
  final StreamController<Map<String, String>> _statusController =
      StreamController<Map<String, String>>.broadcast();
  /// Stream of audio chunks from both microphone and system audio.
  Stream<AudioChunk> get audioStream => _audioController.stream;

  /// Notifications de statut de la capture : `type` ("outputActive",
  /// "outputUnavailable"), et pour une indisponibilité `reason` et `message`.
  Stream<Map<String, String>> get statusStream => _statusController.stream;

  /// Starts audio capture.
  Future<void> startCapture({
    String? inputDeviceId,
    bool outputEnabled = false,
  }) async {
    // Start listening to the event channel BEFORE invoking start
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _onAudioEvent,
      onError: _onAudioError,
    );

    await _methodChannel.invokeMethod<void>('startCapture', <String, dynamic>{
      'inputDeviceId': ?inputDeviceId,
      'outputEnabled': outputEnabled,
    });
  }

  /// Stops all audio capture.
  Future<void> stopCapture() async {
    await _methodChannel.invokeMethod<void>('stopCapture');
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Lists available audio devices.
  Future<List<AudioDeviceEntity>> listDevices() async {
    final List<Map<dynamic, dynamic>>? result = await _methodChannel
        .invokeListMethod<Map<dynamic, dynamic>>('listDevices');

    if (result == null) return const <AudioDeviceEntity>[];

    return result.map((Map<dynamic, dynamic> map) {
      return AudioDeviceEntity(
        id: map['id'] as String,
        name: map['name'] as String,
        isInput: map['isInput'] as bool,
      );
    }).toList();
  }

  /// Whether system audio capture (ScreenCaptureKit) is available.
  Future<bool> isSystemAudioAvailable() async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      'isSystemAudioAvailable',
    );
    return result ?? false;
  }

  /// Vérifie les statuts de permissions (micro et Screen Recording) sans déclencher de dialogue.
  ///
  /// Retourne une map avec les clés "mic" et "screenRecording".
  /// Valeurs possibles : "authorized", "denied", "notDetermined", "restricted", "unknown".
  Future<Map<String, String>> checkPermissions() async {
    final Map<Object?, Object?>? result =
        await _methodChannel.invokeMethod<Map<Object?, Object?>>('checkPermissions');
    if (result == null) return <String, String>{'mic': 'unknown', 'screenRecording': 'unknown'};
    return result.map(
      (Object? k, Object? v) => MapEntry<String, String>(k as String, v as String),
    );
  }

  /// Ouvre le panneau correspondant dans les Réglages Système.
  ///
  /// [pane] : "microphone" ou "screenRecording".
  Future<void> openSystemSettings(String pane) async {
    await _methodChannel.invokeMethod<void>('openSystemSettings', <String, dynamic>{'pane': pane});
  }

  /// Releases resources.
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _audioController.close();
    await _statusController.close();
  }

  void _onAudioEvent(dynamic event) {
    if (event is! Map) return;

    // Événements de statut (non-audio)
    final String? type = event['type'] as String?;
    if (type != null) {
      _statusController.add(<String, String>{
        for (final MapEntry<dynamic, dynamic> e in event.entries)
          if (e.value != null) '${e.key}': '${e.value}',
      });
      return;
    }

    final String? sourceStr = event['source'] as String?;
    final dynamic data = event['data'];
    final int timestampMs = event['timestampMs'] as int? ?? 0;

    if (sourceStr == null || data == null) return;

    final AudioSource source = sourceStr == 'input'
        ? AudioSource.input
        : AudioSource.output;

    final Uint8List bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else {
      return;
    }

    _audioController.add(
      AudioChunk(source: source, data: bytes, timestampMs: timestampMs),
    );
  }

  void _onAudioError(Object error) {
    _audioController.addError(error);
  }
}
