import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings.view_model.g.dart';

File get _prefFile => File('${appDataDirectory()}/prefs.json');

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis et stockage.
@Riverpod(keepAlive: true)
class SettingsViewModel extends _$SettingsViewModel {
  @override
  SettingsState build() {
    _init();
    return SettingsState.initial();
  }

  Future<void> _init() async {
    final List<AudioDeviceEntity> devices =
        await ref.read(audioCaptureChannelProvider).listDevices();
    final List<AudioDeviceEntity> inputDevices =
        devices.where((AudioDeviceEntity d) => d.isInput).toList();

    String? savedMicId;
    bool savedSystemAudio = true;
    try {
      final String raw = await _prefFile.readAsString();
      final Map<String, dynamic> json =
          (jsonDecode(raw) as Map<String, dynamic>);
      savedMicId = json['selected_mic_id'] as String?;
      savedSystemAudio = json['system_audio_enabled'] as bool? ?? true;
    } on Object {
      savedMicId = null;
      savedSystemAudio = true;
    }

    final String? resolvedMicId = savedMicId != null &&
            inputDevices.any((AudioDeviceEntity d) => d.id == savedMicId)
        ? savedMicId
        : null;

    state = state.copyWith(
      storagePath: appDataDirectory(),
      dbSizeMb: 124.0,
      systemAudioEnabled: savedSystemAudio,
      autoStartServer: true,
      availableDevices: inputDevices,
      selectedMicId: resolvedMicId,
    );
  }

  /// Met a jour le microphone selectionne.
  Future<void> updateMic(String id) async {
    state = state.copyWith(selectedMicId: id);
    await _savePrefs(<String, dynamic>{'selected_mic_id': id});
  }

  Future<void> _savePrefs(Map<String, dynamic> data) async {
    final File f = _prefFile;
    await f.parent.create(recursive: true);
    // Lire les prefs existantes, merger, puis écrire
    Map<String, dynamic> existing = <String, dynamic>{};
    try {
      existing = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on Object {
      existing = <String, dynamic>{};
    }
    existing.addAll(data);
    await f.writeAsString(jsonEncode(existing));
  }

  /// Active ou desactive la capture audio systeme.
  Future<void> toggleSystemAudio() async {
    final bool newValue = !state.systemAudioEnabled;
    state = state.copyWith(systemAudioEnabled: newValue);
    await _savePrefs(<String, dynamic>{'system_audio_enabled': newValue});
  }

  /// Active ou desactive le lancement automatique du serveur.
  void toggleAutoStart() {
    state = state.copyWith(autoStartServer: !state.autoStartServer);
  }
}
