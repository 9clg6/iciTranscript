import 'dart:async';

import 'package:core_data/database/dao/document.dao.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_answers/question_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

// Faux des questions/réponses en direct (T4) : LLM piloté à la main, recherche
// de documents réglable, stockage en mémoire. Aucun réseau ni disque.

/// Un flux de réponse ouvert par [ScriptedLlmProvider].
final class ScriptedStream {
  ScriptedStream(this.request) {
    controller = StreamController<String>(
      onCancel: () {
        if (!_closedByTest) cancelled = true;
      },
    );
  }

  final LlmChatRequest request;
  late final StreamController<String> controller;
  bool _closedByTest = false;

  /// L'abonné a annulé le flux avant sa fin (requête abandonnée).
  bool cancelled = false;

  void delta(String text) => controller.add(text);

  void fail(Object error) => controller.addError(error);

  void end() {
    _closedByTest = true;
    unawaited(controller.close());
  }

  /// Envoie [text] d'un bloc puis termine.
  void reply(String text) {
    delta(text);
    end();
  }
}

/// Fournisseur LLM dont chaque réponse est jouée par le test.
final class ScriptedLlmProvider implements LlmProvider {
  final List<ScriptedStream> streams = <ScriptedStream>[];

  List<LlmChatRequest> get requests =>
      streams.map((ScriptedStream s) => s.request).toList();

  ScriptedStream get last => streams.last;

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    final ScriptedStream s = ScriptedStream(request);
    streams.add(s);
    return s.controller.stream;
  }
}

/// Tout le texte envoyé au modèle (consignes + messages).
String requestText(LlmChatRequest r) => <String>[
  r.systemPrompt,
  ...r.messages.map((LlmMessage m) => m.content),
].join('\n');

/// Recherche de documents : résultat fixe, ou futur fourni par le test.
final class FakeDocumentSearch {
  List<DocumentSearchResult> results = <DocumentSearchResult>[];

  /// Si non nul, remplace [results] (recherche lente ou en échec).
  Future<List<DocumentSearchResult>> Function()? pending;

  final List<({String query, int limit})> calls =
      <({String query, int limit})>[];

  Future<List<DocumentSearchResult>> call(String query, {int limit = 5}) {
    calls.add((query: query, limit: limit));
    return pending?.call() ?? Future<List<DocumentSearchResult>>.value(results);
  }
}

/// Stockage des questions en mémoire ; garde l'ordre des écritures.
final class InMemoryQuestionStore implements QuestionStore {
  final Map<String, LiveQuestion> saved = <String, LiveQuestion>{};
  final List<String> log = <String>[];

  @override
  Future<void> saveDetected(LiveQuestion question) async {
    log.add('detected:${question.id}');
    saved[question.id] = question;
  }

  @override
  Future<void> saveAnswer(LiveQuestion question) async {
    log.add('answer:${question.id}');
    saved[question.id] = question;
  }

  @override
  Future<void> delete(String questionId) async {
    log.add('delete:$questionId');
    saved.remove(questionId);
  }

  @override
  Future<List<LiveQuestion>> forSession(String sessionId) async =>
      saved.values.where((LiveQuestion q) => q.sessionId == sessionId).toList();
}

/// Service monté sur les faux, prêt pour la session `s1`.
final class LiveAnswersHarness {
  LiveAnswersHarness({
    this.modelId = 'claude-haiku-5-5',
    bool modelReady = true,
  }) : _modelReady = modelReady {
    service = LiveAnswersService(
      resolveModel: () async {
        resolveCalls++;
        return _modelReady
            ? LiveAnswerModel(provider: llm, modelId: modelId)
            : null;
      },
      searchDocuments: search.call,
      store: store,
    )..start('s1');
  }

  final ScriptedLlmProvider llm = ScriptedLlmProvider();
  final FakeDocumentSearch search = FakeDocumentSearch();
  final InMemoryQuestionStore store = InMemoryQuestionStore();
  final String modelId;
  bool _modelReady;
  int resolveCalls = 0;
  late final LiveAnswersService service;

  set modelReady(bool v) => _modelReady = v;

  List<LiveQuestion> get questions => service.questions;

  LiveQuestion get only {
    if (questions.length != 1) {
      throw StateError('attendu 1 question, vu ${questions.length}');
    }
    return questions.single;
  }

  int _n = 0;

  /// Segment finalisé à [atMs] ms du début de la session.
  TranscriptSegmentEntity segment(
    String text, {
    AudioSource source = AudioSource.output,
    int atMs = 60000,
    String? id,
  }) => TranscriptSegmentEntity(
    id: id ?? 'seg-${++_n}',
    sessionId: 's1',
    source: source,
    text: text,
    timestampMs: atMs,
    createdAt: DateTime(2026, 11, 22, 10),
  );

  /// Un autre participant dit [text].
  TranscriptSegmentEntity hear(
    String text, {
    int atMs = 60000,
    int? speaker = 1,
    AudioSource source = AudioSource.output,
  }) {
    final TranscriptSegmentEntity s = segment(text, atMs: atMs, source: source);
    service.onSegmentFinalized(s, speaker: speaker);
    return s;
  }
}
