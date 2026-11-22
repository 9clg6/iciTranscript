import 'package:ici_transcript/application/services/live_answers/live_question.dart';

/// Questions détectées gardées avec la note.
abstract interface class QuestionStore {
  /// Range [question] à sa détection, sans réponse.
  Future<void> saveDetected(LiveQuestion question);

  /// Range l'état final de [question] : réponse, modèle, sources, refus ou
  /// échec.
  Future<void> saveAnswer(LiveQuestion question);

  /// Supprime la question (« Ignorer »).
  Future<void> delete(String questionId);

  /// Questions de [sessionId], dans l'ordre de la réunion.
  Future<List<LiveQuestion>> forSession(String sessionId);
}
