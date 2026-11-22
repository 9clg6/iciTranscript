import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';

part 'detected_question.dao.g.dart';

/// Source d'une réponse rangée en JSON dans `detected_questions.sources`.
typedef StoredAnswerSource = ({
  String documentId,
  String title,
  String excerpt,
});

/// DAO des questions détectées en direct : sauvées à la détection,
/// complétées à la fin du flux, supprimées avec leur session (trigger).
///
/// ponytail: le schéma v2 n'a pas encore `status`, `speaker` ni `source`
/// (colonnes de la prochaine migration, en attente d'une autre branche) :
/// [insertDetected] accepte déjà [speaker]/[source] sans les ranger, et
/// [saveAnswer]/[setStatus] ne rangent pas encore le statut. Les points à
/// compléter sont marqués « colonnes à venir ».
@DriftAccessor(tables: <Type>[DetectedQuestions])
class DetectedQuestionDao extends DatabaseAccessor<AppDatabase>
    with _$DetectedQuestionDaoMixin {
  /// Crée le DAO.
  DetectedQuestionDao(super.db);

  /// Range une question détectée, sans réponse (statut `unanswered`).
  Future<void> insertDetected({
    required String id,
    required String sessionId,
    required String question,
    required int timestampMs,
    required DateTime createdAt,
    String? segmentId,
    String? speaker,
    String? source,
  }) {
    // Colonnes à venir : status 'unanswered', speaker, source.
    return into(detectedQuestions).insertOnConflictUpdate(
      DetectedQuestionsCompanion.insert(
        id: id,
        sessionId: sessionId,
        segmentId: Value<String?>(segmentId),
        question: question,
        timestampMs: timestampMs,
        createdAt: createdAt.toIso8601String(),
      ),
    );
  }

  /// Complète la question [id] : réponse, modèle et sources (statut
  /// `answered`, ou `truncated` si [truncated]).
  Future<void> saveAnswer(
    String id, {
    required String answer,
    required String model,
    required List<StoredAnswerSource> sources,
    bool truncated = false,
  }) {
    // Colonne à venir : status (truncated ? 'truncated' : 'answered').
    return _write(
      id,
      DetectedQuestionsCompanion(
        answer: Value<String?>(answer),
        answerModel: Value<String?>(model),
        sources: Value<String?>(
          jsonEncode(<Map<String, String>>[
            for (final StoredAnswerSource s in sources)
              <String, String>{
                'documentId': s.documentId,
                'title': s.title,
                'excerpt': s.excerpt,
              },
          ]),
        ),
      ),
    );
  }

  /// Range [status] (`declined`, `failed`) : la question reste sans réponse.
  Future<void> setStatus(String id, String status) {
    // Colonne à venir : status.
    return _write(
      id,
      const DetectedQuestionsCompanion(
        answer: Value<String?>(null),
        answerModel: Value<String?>(null),
        sources: Value<String?>(null),
      ),
    );
  }

  /// Questions de [sessionId], par `timestampMs` croissant.
  Future<List<DetectedQuestion>> forSession(String sessionId) {
    return (select(detectedQuestions)
          ..where(($DetectedQuestionsTable t) => t.sessionId.equals(sessionId))
          ..orderBy(<OrderingTerm Function($DetectedQuestionsTable)>[
            ($DetectedQuestionsTable t) => OrderingTerm.asc(t.timestampMs),
          ]))
        .get();
  }

  /// Supprime la question [id].
  Future<void> deleteById(String id) {
    return (delete(
      detectedQuestions,
    )..where(($DetectedQuestionsTable t) => t.id.equals(id))).go();
  }

  Future<void> _write(String id, DetectedQuestionsCompanion values) {
    return (update(
      detectedQuestions,
    )..where(($DetectedQuestionsTable t) => t.id.equals(id))).write(values);
  }
}
