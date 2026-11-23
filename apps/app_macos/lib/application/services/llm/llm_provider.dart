/// Fournisseurs LLM connus. `name` sert de compte dans le trousseau.
enum LlmProviderId {
  /// Claude (API Anthropic), cle API.
  anthropic,

  /// OpenAI, cle API.
  openai,

  /// Gemini (API Google AI), cle API.
  gemini,

  /// Ollama local, sans cle.
  ollama,
}

/// Role d'un message de conversation.
enum LlmRole {
  /// Message de l'utilisateur.
  user,

  /// Reponse du modele.
  assistant,
}

/// Message d'une conversation envoyee au modele.
class LlmMessage {
  /// Cree un [LlmMessage].
  const LlmMessage({required this.role, required this.content});

  /// Auteur du message.
  final LlmRole role;

  /// Texte du message.
  final String content;
}

/// Requete de chat, commune a tous les fournisseurs.
class LlmChatRequest {
  /// Cree une [LlmChatRequest].
  const LlmChatRequest({
    required this.systemPrompt,
    required this.messages,
    required this.maxTokens,
    this.model,
    this.preferLowLatency = false,
  });

  /// Consignes systeme.
  final String systemPrompt;

  /// Conversation, du plus ancien au plus recent.
  final List<LlmMessage> messages;

  /// Nombre maximal de jetons generes.
  final int maxTokens;

  /// Modele demande ; null = modele rapide par defaut du fournisseur.
  final String? model;

  /// Réponse courte où la latence prime (réponses en direct). Un
  /// fournisseur qui a un réglage pour cela l'applique, les autres
  /// l'ignorent.
  final bool preferLowLatency;
}

/// Fournisseur LLM : une requete de chat -> un flux de morceaux de texte.
///
/// Annuler l'abonnement abandonne la requete HTTP. Les erreurs sont des
/// [LlmException] et ne contiennent jamais la cle API.
abstract interface class LlmProvider {
  /// Envoie [request] et emet le texte de la reponse au fil de l'eau.
  Stream<String> streamChat(LlmChatRequest request);
}

/// Erreur d'un fournisseur LLM. Le message ne contient ni la cle API ni le
/// corps de la reponse (certaines API y recopient la cle).
class LlmException implements Exception {
  /// Cree une [LlmException].
  const LlmException(this.message);

  /// Description sans donnee sensible.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Cle API refusee par le fournisseur.
class LlmInvalidKeyException extends LlmException {
  /// Cree une [LlmInvalidKeyException].
  const LlmInvalidKeyException(String provider)
    : super('$provider : clé API invalide');
}

/// Limite de debit atteinte chez le fournisseur.
class LlmRateLimitedException extends LlmException {
  /// Cree une [LlmRateLimitedException].
  const LlmRateLimitedException(String provider)
    : super('$provider : limite de débit atteinte');
}

/// Fournisseur injoignable (reseau coupe, serveur local arrete).
class LlmUnreachableException extends LlmException {
  /// Cree une [LlmUnreachableException].
  const LlmUnreachableException(String provider)
    : super('$provider : injoignable');
}

/// Réponse reçue mais illisible (JSON attendu absent, coupé ou d'une autre
/// forme).
class LlmMalformedAnswerException extends LlmException {
  /// Crée une [LlmMalformedAnswerException].
  const LlmMalformedAnswerException() : super('réponse du modèle illisible');
}
