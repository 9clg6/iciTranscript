import 'package:json_annotation/json_annotation.dart';

/// Statut d'une session de transcription.
@JsonEnum()
enum SessionStatus {
  /// Session en cours.
  active,

  /// Session terminee avec succes.
  completed,

  /// Session terminee en erreur.
  error,

  /// Session restee active apres un arret brutal de l'app, close au
  /// lancement suivant (duree tiree de son dernier segment).
  interrupted,
}
