import 'package:freezed_annotation/freezed_annotation.dart';

part 'english_feedback.entity.freezed.dart';
part 'english_feedback.entity.g.dart';

/// Une correction unitaire : segment original vs version amelioree.
@freezed
abstract class EnglishCorrectionEntity with _$EnglishCorrectionEntity {
  /// Cree une instance de [EnglishCorrectionEntity].
  const factory EnglishCorrectionEntity({
    /// Phrase ou tournure telle que prononcee par l'utilisateur.
    required String original,

    /// Version corrigee / amelioree proposee.
    required String corrected,

    /// Categorie libre renvoyee par le modele
    /// (ex: conjugation, vocabulary, expression, grammar).
    required String category,

    /// Explication courte de la correction (en francais).
    required String explanation,
  }) = _EnglishCorrectionEntity;

  /// Construit l'entite depuis un JSON.
  factory EnglishCorrectionEntity.fromJson(Map<String, dynamic> json) =>
      _$EnglishCorrectionEntityFromJson(json);
}

/// Retour complet du coach d'anglais pour une session.
@freezed
abstract class EnglishFeedbackEntity with _$EnglishFeedbackEntity {
  /// Cree une instance de [EnglishFeedbackEntity].
  const factory EnglishFeedbackEntity({
    /// Liste des corrections proposees.
    @Default(<EnglishCorrectionEntity>[])
    List<EnglishCorrectionEntity> corrections,

    /// Appreciation globale du niveau (optionnelle).
    String? overall,
  }) = _EnglishFeedbackEntity;

  /// Construit l'entite depuis un JSON.
  factory EnglishFeedbackEntity.fromJson(Map<String, dynamic> json) =>
      _$EnglishFeedbackEntityFromJson(json);
}
