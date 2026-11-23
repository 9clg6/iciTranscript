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
/// `status` : unanswered, answered, shortened, declined, truncated, failed.
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
    return into(detectedQuestions).insertOnConflictUpdate(
      DetectedQuestionsCompanion.insert(
        id: id,
        sessionId: sessionId,
        segmentId: Value<String?>(segmentId),
        question: question,
        timestampMs: timestampMs,
        createdAt: createdAt.toIso8601String(),
        status: const Value<String>('unanswered'),
        speaker: Value<String?>(speaker),
        source: Value<String?>(source),
      ),
    );
  }

  /// Complète la question [id] : réponse, modèle et sources (statut
  /// `answered`, `truncated` si [truncated], sinon `shortened` si
  /// [shortened]).
  Future<void> saveAnswer(
    String id, {
    required String answer,
    required String model,
    required List<StoredAnswerSource> sources,
    bool truncated = false,
    bool shortened = false,
  }) {
    return _write(
      id,
      DetectedQuestionsCompanion(
        answer: Value<String?>(answer),
        answerModel: Value<String?>(model),
        // Coupée prime sur raccourcie : un seul état par ligne.
        status: Value<String>(
          truncated
              ? 'truncated'
              : shortened
              ? 'shortened'
              : 'answered',
        ),
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
    return _write(
      id,
      DetectedQuestionsCompanion(
        status: Value<String>(status),
        answer: const Value<String?>(null),
        answerModel: const Value<String?>(null),
        sources: const Value<String?>(null),
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
