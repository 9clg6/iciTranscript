import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.local.model.freezed.dart';
part 'session.local.model.g.dart';

/// Modele de donnees local pour une session de transcription (SQLite/Drift).
@freezed
abstract class SessionLocalModel with _$SessionLocalModel {
  /// Cree une instance de [SessionLocalModel].
  const factory SessionLocalModel({
    /// Identifiant unique de la session.
    required String id,

    /// Titre de la session.
    required String title,

    /// Date de creation au format ISO 8601.
    required String createdAt,

    /// Date de derniere mise a jour au format ISO 8601.
    required String updatedAt,

    /// Duree totale en secondes.
    int? durationSeconds,

    /// Statut de la session (active, completed, error).
    required String status,

    /// Identifiant de l'evenement d'agenda lie.
    String? calendarEventId,

    /// Titre de l'evenement d'agenda lie.
    String? calendarEventTitle,

    /// Noms des participants, tableau JSON (null = aucun).
    String? attendees,

    /// Audio envoye en temps reel a la transcription en ligne (ms).
    @Default(0) int cloudRealtimeMs,

    /// Audio envoye par lot a la transcription en ligne (ms).
    @Default(0) int cloudBatchMs,
  }) = _SessionLocalModel;

  /// Cree une instance depuis un JSON.
  factory SessionLocalModel.fromJson(Map<String, dynamic> json) =>
      _$SessionLocalModelFromJson(json);
}
