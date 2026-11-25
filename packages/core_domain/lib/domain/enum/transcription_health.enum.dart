/// Etat de la transcription en direct, vu par l'utilisateur.
///
/// L'enregistrement continue dans tous les cas : seul le texte en direct
/// peut etre retarde ([recovering]) ou arrete ([failed]).
enum TranscriptionHealth {
  /// Serveur et connexions en marche.
  healthy,

  /// Serveur relance ou connexion retablie en cours.
  recovering,

  /// Relances abandonnees : plus de texte en direct pour cette session.
  failed,

  /// Moteur en ligne : la cle est refusee ; l'enregistrement continue, le
  /// texte attend une cle valide (rattrapage).
  keyRejected,
}
