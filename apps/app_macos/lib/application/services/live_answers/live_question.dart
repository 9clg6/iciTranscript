import 'package:core_domain/domain/enum/audio_source.enum.dart';

/// Où en est une question détectée en direct.
enum LiveQuestionStatus {
  /// Listée, sans réponse (en attente, retenue pour le modèle local, ou
  /// arrêtée en cours de flux).
  detected,

  /// Réponse en cours de génération.
  answering,

  /// Réponse reçue (éventuellement tronquée, voir [LiveQuestion.truncated]).
  answered,

  /// Le modèle a répondu `NO_ANSWER` : rien d'utile à proposer.
  declined,

  /// La génération a échoué (voir [LiveQuestion.failure]).
  failed,

  /// Aucun modèle prêt (envoi coupé et modèle local absent).
  needsModel,
}

/// Raison d'un échec, pour le message affiché.
enum LiveAnswerFailure {
  /// Clé API refusée.
  invalidKey,

  /// Limite de débit du fournisseur.
  rateLimited,

  /// Fournisseur injoignable.
  unreachable,

  /// Réponse illisible ou vide.
  malformed,

  /// Autre erreur.
  other,
}

/// Extrait d'un document cité par une réponse.
class AnswerSource {
  /// Crée une [AnswerSource].
  const AnswerSource({
    required this.documentId,
    required this.title,
    required this.excerpt,
  });

  /// Document d'origine.
  final String documentId;

  /// Titre du document.
  final String title;

  /// Passage fourni au modèle.
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      other is AnswerSource &&
      other.documentId == documentId &&
      other.title == title &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(documentId, title, excerpt);

  @override
  String toString() => 'AnswerSource($documentId, $title)';
}

const Object _keep = Object();

/// Question entendue pendant une réunion et la réponse proposée.
class LiveQuestion {
  /// Crée une [LiveQuestion].
  const LiveQuestion({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.timestampMs,
    this.segmentId,
    this.source = AudioSource.output,
    this.speaker,
    this.status = LiveQuestionStatus.detected,
    this.answer = '',
    this.truncated = false,
    this.shortened = false,
    this.failure,
    this.sources = const <AnswerSource>[],
    this.model,
    this.onDemand = false,
  });

  /// Identifiant.
  final String id;

  /// Session (note) de la question.
  final String sessionId;

  /// Segment d'où vient la question, s'il est connu.
  final String? segmentId;

  /// Texte de la question.
  final String text;

  /// Qui l'a dite : micro (l'utilisateur) ou son du Mac (les autres).
  final AudioSource source;

  /// Interlocuteur (0, 1, …) sur le son du Mac, null si inconnu.
  final int? speaker;

  /// Décalage depuis le début de la réunion, en millisecondes.
  final int timestampMs;

  /// État.
  final LiveQuestionStatus status;

  /// Réponse affichée (partielle pendant le flux) ; vide sans réponse.
  final String answer;

  /// La réponse s'arrête au milieu d'une phrase.
  final bool truncated;

  /// Des lignes reçues ne sont pas montrées (réponse trop longue).
  // ponytail: pas rangé en base ; une note rouverte ne le signale plus.
  final bool shortened;

  /// Raison de l'échec quand [status] vaut `failed`.
  final LiveAnswerFailure? failure;

  /// Extraits cités, dans l'ordre des repères `[S1]`, `[S2]`… de [answer].
  final List<AnswerSource> sources;

  /// Modèle qui a produit la réponse.
  final String? model;

  /// Retenue pour le modèle local : la réponse se demande à la main.
  final bool onDemand;

  /// Copie modifiée ; [failure] et [model] acceptent null explicitement.
  LiveQuestion copyWith({
    LiveQuestionStatus? status,
    String? answer,
    bool? truncated,
    bool? shortened,
    Object? failure = _keep,
    List<AnswerSource>? sources,
    Object? model = _keep,
    bool? onDemand,
  }) => LiveQuestion(
    id: id,
    sessionId: sessionId,
    segmentId: segmentId,
    text: text,
    source: source,
    speaker: speaker,
    timestampMs: timestampMs,
    status: status ?? this.status,
    answer: answer ?? this.answer,
    truncated: truncated ?? this.truncated,
    shortened: shortened ?? this.shortened,
    failure: identical(failure, _keep)
        ? this.failure
        : failure as LiveAnswerFailure?,
    sources: sources ?? this.sources,
    model: identical(model, _keep) ? this.model : model as String?,
    onDemand: onDemand ?? this.onDemand,
  );
}
