import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/detected_question.dao.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
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
          shortened: question.shortened,
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
    final StoredStatus s = storedStatus(
      row.status,
      hasAnswer: (row.answer ?? '').trim().isNotEmpty,
    );
    return LiveQuestion(
      id: row.id,
      sessionId: row.sessionId,
      segmentId: row.segmentId,
      text: row.question,
      source: AudioSource.values.asNameMap()[row.source] ?? AudioSource.output,
      speaker: int.tryParse(row.speaker ?? ''),
      timestampMs: row.timestampMs,
      status: s.status,
      truncated: s.truncated,
      shortened: s.shortened,
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

/// Statut rangé en base → état relu ; seul endroit qui le lit.
/// `shortened` = répondue, texte montré raccourci. Valeur inconnue (rangée
/// par une version plus récente) = répondue si un texte de réponse est
/// rangé, sinon sans réponse.
typedef StoredStatus = ({
  LiveQuestionStatus status,
  bool truncated,
  bool shortened,
});

StoredStatus storedStatus(String stored, {required bool hasAnswer}) =>
    switch (stored) {
      'unanswered' => (
        status: LiveQuestionStatus.detected,
        truncated: false,
        shortened: false,
      ),
      'truncated' => (
        status: LiveQuestionStatus.answered,
        truncated: true,
        shortened: false,
      ),
      'shortened' => (
        status: LiveQuestionStatus.answered,
        truncated: false,
        shortened: true,
      ),
      'declined' => (
        status: LiveQuestionStatus.declined,
        truncated: false,
        shortened: false,
      ),
      'failed' => (
        status: LiveQuestionStatus.failed,
        truncated: false,
        shortened: false,
      ),
      'answered' => (
        status: LiveQuestionStatus.answered,
        truncated: false,
        shortened: false,
      ),
      // Valeur qu'une version plus récente aurait rangée : la réponse reste
      // montrée ; sans texte, la question reste sans réponse.
      _ => (
        status: hasAnswer
            ? LiveQuestionStatus.answered
            : LiveQuestionStatus.detected,
        truncated: false,
        shortened: false,
      ),
    };
