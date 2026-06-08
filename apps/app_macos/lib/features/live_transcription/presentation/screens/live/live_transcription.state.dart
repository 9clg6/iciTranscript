import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';

part 'live_transcription.state.freezed.dart';

/// Etat de l'ecran de transcription en direct.
@Freezed(copyWith: true)
abstract class LiveTranscriptionState with _$LiveTranscriptionState {
  /// Cree une instance de [LiveTranscriptionState].
  const factory LiveTranscriptionState({
    /// Liste des segments de transcription de la session courante.
    required List<TranscriptSegmentEntity> segments,

    /// Indique si un enregistrement est en cours.
    @Default(false) bool isRecording,

    /// Indique si l'enregistrement est en pause.
    @Default(false) bool isPaused,

    /// Duree actuelle de la session.
    @Default(Duration.zero) Duration duration,

    /// Etat du serveur de transcription.
    @Default(ServerState.stopped) ServerState serverState,

    /// Titre de la session en cours.
    String? sessionTitle,

    /// Statut de la permission microphone.
    /// Valeurs : "authorized", "denied", "notDetermined", "restricted", "unknown".
    @Default('unknown') String micPermission,

    /// Statut de la permission Screen Recording.
    /// Valeurs : "authorized", "denied", "notDetermined", "unknown".
    @Default('unknown') String screenRecordingPermission,

    /// Indique si l'option coach d'anglais est activée.
    @Default(false) bool isCoachEnabled,

    /// Indique si la traduction temps réel est activée.
    @Default(false) bool isTranslationEnabled,

    /// Langue source de la traduction (code ISO, ex: "en").
    @Default('en') String translationFrom,

    /// Langue cible de la traduction (code ISO, ex: "fr").
    @Default('fr') String translationTo,

    /// Traductions par segment (id segment → texte traduit).
    @Default(<String, String>{}) Map<String, String> translations,

    /// Retour du coach d'anglais (null si pas encore généré).
    EnglishFeedbackEntity? feedback,

    /// Indique si l'analyse de l'anglais est en cours.
    @Default(false) bool isFeedbackLoading,

    /// Étape courante du setup Ollama.
    @Default(OllamaSetupStage.idle) OllamaSetupStage ollamaSetupStage,

    /// Progression du setup Ollama (0.0 – 1.0).
    @Default(0.0) double ollamaSetupProgress,

    /// Message d'erreur du setup Ollama.
    String? ollamaSetupError,
  }) = _LiveTranscriptionState;

  /// Etat initial par defaut.
  factory LiveTranscriptionState.initial() =>
      const LiveTranscriptionState(segments: <TranscriptSegmentEntity>[]);
}
