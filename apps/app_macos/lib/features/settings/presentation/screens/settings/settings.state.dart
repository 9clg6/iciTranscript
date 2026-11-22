import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.state.freezed.dart';

/// Résultat du bouton « Tester » d'un fournisseur LLM.
enum LlmTestStatus {
  /// Requête en cours.
  testing,

  /// Réponse reçue.
  ok,

  /// Clé refusée.
  invalidKey,

  /// Limite de débit atteinte.
  rateLimited,

  /// Fournisseur injoignable ou muet.
  unreachable,

  /// Autre échec.
  failed,
}

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

    /// Port du serveur ML (voxmlx-serve default: 8000).
    @Default('8000') String serverPort,

    /// Chemin de stockage de la base de donnees.
    @Default('') String storagePath,

    /// Taille de la base de donnees en Mo.
    @Default(0.0) double dbSizeMb,

    /// Liste des peripheriques audio disponibles.
    required List<AudioDeviceEntity> availableDevices,

    /// Envoi à un service LLM en ligne autorisé (coupé par défaut).
    @Default(false) bool llmCloudAllowed,

    /// Fournisseur LLM choisi ; null = repli automatique.
    LlmProviderId? llmPreferred,

    /// Fournisseur LLM réellement utilisé (choix, autorisation et clés).
    @Default(LlmProviderId.ollama) LlmProviderId llmActive,

    /// Modèles choisis par fournisseur ; absent = modèle par défaut.
    @Default(<LlmProviderId, String>{}) Map<LlmProviderId, String> llmModels,

    /// 4 derniers caractères de chaque clé rangée (jamais la clé entière).
    @Default(<LlmProviderId, String>{})
    Map<LlmProviderId, String> llmKeySuffixes,

    /// Fournisseurs dont le trousseau a refusé la lecture ou l'écriture.
    @Default(<LlmProviderId>{}) Set<LlmProviderId> llmKeyErrors,

    /// Dernier résultat de « Tester » par fournisseur.
    @Default(<LlmProviderId, LlmTestStatus>{})
    Map<LlmProviderId, LlmTestStatus> llmTests,
  }) = _SettingsState;

  /// Etat initial par defaut.
  factory SettingsState.initial() =>
      const SettingsState(availableDevices: <AudioDeviceEntity>[]);
}
