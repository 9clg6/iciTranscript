import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/detected_question.dao.dart';
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

/// [QuestionStore] sur la base Drift de l'app.
class DriftQuestionStore implements QuestionStore {
  /// Crée le stockage sur [dao].
  DriftQuestionStore(this._dao);

  final DetectedQuestionDao _dao;

  @override
  Future<void> saveDetected(LiveQuestion question) => _dao.insertDetected(
    id: question.id,
    sessionId: question.sessionId,
    segmentId: question.segmentId,
    question: question.text,
    timestampMs: question.timestampMs,
    createdAt: clock.now(),
    speaker: question.speaker?.toString(),
    source: question.source.name,
  );

  @override
  Future<void> saveAnswer(LiveQuestion question) async {
    switch (question.status) {
      case LiveQuestionStatus.answered:
        await _dao.saveAnswer(
          question.id,
          answer: question.answer,
          model: question.model ?? '',
          truncated: question.truncated,
          sources: <StoredAnswerSource>[
            for (final AnswerSource s in question.sources)
              (documentId: s.documentId, title: s.title, excerpt: s.excerpt),
          ],
        );
      case LiveQuestionStatus.declined || LiveQuestionStatus.failed:
        await _dao.setStatus(question.id, question.status.name);
      case LiveQuestionStatus.detected ||
          LiveQuestionStatus.answering ||
          LiveQuestionStatus.needsModel:
        return;
    }
  }

  @override
  Future<void> delete(String questionId) => _dao.deleteById(questionId);

  @override
  Future<List<LiveQuestion>> forSession(String sessionId) async =>
      <LiveQuestion>[
        for (final DetectedQuestion row in await _dao.forSession(sessionId))
          _read(row),
      ];

  static LiveQuestion _read(DetectedQuestion row) {
    // Colonnes à venir : `row.status`, `row.speaker`, `row.source`. En
    // attendant, le statut se déduit de la réponse rangée.
    final ({LiveQuestionStatus status, bool truncated}) s = storedStatus(
      row.answer != null ? 'answered' : 'unanswered',
    );
    return LiveQuestion(
      id: row.id,
      sessionId: row.sessionId,
      segmentId: row.segmentId,
      text: row.question,
      timestampMs: row.timestampMs,
      status: s.status,
      truncated: s.truncated,
      answer: row.answer ?? '',
      model: row.answerModel,
      sources: _sources(row.sources),
    );
  }

  static List<AnswerSource> _sources(String? json) {
    if (json == null) return const <AnswerSource>[];
    try {
      return <AnswerSource>[
        for (final Object? e in jsonDecode(json) as List<Object?>)
          if (e case {
            'documentId': final String id,
            'title': final String title,
            'excerpt': final String excerpt,
          })
            AnswerSource(documentId: id, title: title, excerpt: excerpt),
      ];
    } on Object {
      return const <AnswerSource>[];
    }
  }
}

/// Statut rangé en base (`unanswered`, `answered`, `truncated`, `declined`,
/// `failed`) → état relu. Inconnu = sans réponse.
({LiveQuestionStatus status, bool truncated}) storedStatus(String stored) =>
    switch (stored) {
      'answered' => (status: LiveQuestionStatus.answered, truncated: false),
      'truncated' => (status: LiveQuestionStatus.answered, truncated: true),
      'declined' => (status: LiveQuestionStatus.declined, truncated: false),
      'failed' => (status: LiveQuestionStatus.failed, truncated: false),
      _ => (status: LiveQuestionStatus.detected, truncated: false),
    };
