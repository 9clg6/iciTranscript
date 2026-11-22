import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.state.freezed.dart';

/// Etat de l'ecran des reglages de l'application.
@Freezed(copyWith: true)
abstract class SettingsState with _$SettingsState {
  /// Cree une instance de [SettingsState].
  const factory SettingsState({
    /// Identifiant du microphone selectionne.
    String? selectedMicId,

    /// Indique si la capture audio systeme est activee.
    @Default(true) bool systemAudioEnabled,

    /// Indique si le serveur ML doit demarrer automatiquement.
    @Default(true) bool autoStartServer,

    /// Chemin de stockage de la base de donnees.
    @Default('') String storagePath,

    /// Taille de la base de donnees en Mo.
    @Default(0.0) double dbSizeMb,

    /// Liste des peripheriques audio disponibles.
    required List<AudioDeviceEntity> availableDevices,
  }) = _SettingsState;

  /// Etat initial par defaut.
  factory SettingsState.initial() =>
      const SettingsState(availableDevices: <AudioDeviceEntity>[]);
}
