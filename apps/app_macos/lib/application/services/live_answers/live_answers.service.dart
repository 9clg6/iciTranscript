import 'dart:async';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/answer_prompt.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_answers/question_gate.dart';
import 'package:ici_transcript/application/services/live_answers/question_store.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:rxdart/rxdart.dart';

/// Avec le modèle local, réponses automatiques ? Non : le serveur de
/// transcription et le LLM local partagent la machine ; les questions sont
/// listées et la réponse se demande. La seule bascule.
const bool kAutoAnswerWithLocalModel = false;

/// La même question redite dans cette fenêtre (temps de la réunion) n'est
/// traitée qu'une fois.
const Duration kQuestionDedupeWindow = Duration(seconds: 30);

/// Attente maximale de la recherche de documents ; au-delà, la requête part
/// sans extrait.
const Duration kDocumentSearchBudget = Duration(milliseconds: 150);

/// Contexte donné au modèle : ce qui a été dit dans cette fenêtre…
const Duration kContextWindow = Duration(minutes: 3);

/// … dans la limite de ce nombre de caractères (le plus récent gardé).
const int kMaxContextChars = 4000;

/// Extraits de documents demandés à la recherche.
const int kMaxExcerpts = 3;

/// Recherche d'extraits, de la forme de `DocumentLibrary.search`.
typedef ExcerptSearch =
    Future<List<DocumentExcerpt>> Function(String question, {int limit});

/// Modèle qui répond : fournisseur, id du modèle, local ou en ligne.
class LiveAnswerModel {
  /// Crée un [LiveAnswerModel].
  const LiveAnswerModel({
    required this.provider,
    required this.modelId,
    this.isLocal = false,
  });

  /// Fournisseur LLM.
  final LlmProvider provider;

  /// Modèle utilisé (gardé avec la réponse).
  final String modelId;

  /// Modèle local (Ollama) : réponses à la demande.
  final bool isLocal;
}

typedef _Line = ({TranscriptSegmentEntity segment, int? speaker});

/// Questions et réponses en direct d'une session.
///
/// Les segments FINAUX des deux sources entrent par [onSegmentFinalized] ;
/// la porte ([detectQuestions]) choisit les questions des autres. Une seule
/// génération à la fois ; une question arrivée pendant ce temps attend dans
/// une place unique où la plus récente gagne (celle qu'elle remplace reste
/// listée « détectée », lançable à la main). Le modèle est résolu à chaque
/// question.
class LiveAnswersService {
  /// Crée le service.
  LiveAnswersService({
    required Future<LiveAnswerModel?> Function() resolveModel,
    required ExcerptSearch searchDocuments,
    required QuestionStore store,
  }) : _resolveModel = resolveModel,
       _search = searchDocuments,
       _store = store;

  final Future<LiveAnswerModel?> Function() _resolveModel;
  final ExcerptSearch _search;
  final QuestionStore _store;
  final Log _log = Log.named('LiveAnswersService');

  final BehaviorSubject<List<LiveQuestion>> _subject =
      BehaviorSubject<List<LiveQuestion>>.seeded(const <LiveQuestion>[]);
  final List<LiveQuestion> _questions = <LiveQuestion>[];
  final List<_Line> _context = <_Line>[];
  final Set<String> _seenSegments = <String>{};
  final Map<int, int?> _dictation = <int, int?>{};

  String? _sessionId;
  bool _paused = false;
  int _nextId = 0;

  // File : une génération en vol, une place d'attente.
  String? _inFlight;
  int _run = 0;
  StreamSubscription<String>? _answer;
  ({String id, bool manual})? _waiting;

  /// Questions, dans l'ordre de détection.
  List<LiveQuestion> get questions =>
      List<LiveQuestion>.unmodifiable(_questions);

  /// [questions] à chaque changement (réponse partielle comprise).
  Stream<List<LiveQuestion>> get questionsStream => _subject.stream;

  /// Ouvre la session [sessionId] : tout l'état précédent est oublié.
  void start(String sessionId) {
    _cancelAnswer();
    _questions.clear();
    _context.clear();
    _seenSegments.clear();
    _dictation.clear();
    _sessionId = sessionId;
    _paused = false;
    _emit();
  }

  /// Rien n'est détecté jusqu'à [resume].
  void pause() => _paused = true;

  /// Reprend la détection.
  void resume() => _paused = false;

  /// Ferme la session : la réponse en vol est abandonnée (rien sauvé, la
  /// question reste « sans réponse »).
  Future<void> stop() async {
    _sessionId = null;
    _cancelAnswer();
    for (int i = 0; i < _questions.length; i++) {
      if (_questions[i].status == LiveQuestionStatus.answering) {
        _questions[i] = _questions[i].copyWith(
          status: LiveQuestionStatus.detected,
          answer: '',
        );
      }
    }
    _emit();
  }

  /// Libère le service (fin de l'app).
  Future<void> dispose() async {
    await stop();
    await _subject.close();
  }

  /// Plage de dictée (raccourci tenu de [startMs] à [endMs], ouverte si
  /// null) : la parole du micro qui y tombe n'est ni contexte ni question.
  void markDictation({required int startMs, int? endMs}) =>
      _dictation[startMs] = endMs;

  /// Segment final d'une des deux sources : contexte, puis porte.
  void onSegmentFinalized(TranscriptSegmentEntity segment, {int? speaker}) {
    if (!_accepts(segment)) return;
    final int known = _context.indexWhere(
      (_Line l) => l.segment.id == segment.id,
    );
    if (known >= 0) {
      _context[known] = (segment: segment, speaker: speaker);
    } else {
      _context.add((segment: segment, speaker: speaker));
    }
    if (!_seenSegments.add(segment.id)) return;
    for (final String text in detectQuestions(segment)) {
      if (_isDuplicate(text, segment.timestampMs)) continue;
      _enqueue(_detect(segment, text, speaker), manual: false);
    }
  }

  /// « Répondre à cette phrase » : [segment] devient une question et part.
  void answerSegment(TranscriptSegmentEntity segment, {int? speaker}) {
    if (!_accepts(segment)) return;
    _enqueue(_detect(segment, segment.text.trim(), speaker), manual: true);
  }

  /// « Répondre » : la dernière phrase des autres devient une question.
  void answerLatestFromOthers() {
    if (_sessionId == null) return;
    final _Line? last = _context.lastWhereOrNull(
      (_Line l) => l.segment.source == AudioSource.output,
    );
    if (last != null) answerSegment(last.segment, speaker: last.speaker);
  }

  /// « Réessayer » / « Proposer une réponse ».
  void retry(String questionId) {
    final int i = _indexOf(questionId);
    if (i < 0 || questionId == _inFlight) return;
    _put(
      _questions[i].copyWith(
        status: LiveQuestionStatus.detected,
        answer: '',
        failure: null,
        truncated: false,
        sources: const <AnswerSource>[],
      ),
    );
    _enqueue(_questions[i], manual: true);
  }

  /// « Ignorer » : retirée de la liste et du stockage ; si elle était en
  /// vol, sa requête est abandonnée et la question en attente part.
  void dismiss(String questionId) {
    final bool wasInFlight = questionId == _inFlight;
    if (wasInFlight) _cancelAnswer(keepWaiting: true);
    if (_waiting?.id == questionId) _waiting = null;
    _questions.removeWhere((LiveQuestion q) => q.id == questionId);
    _emit();
    _guard(_store.delete(questionId));
    if (wasInFlight) _next();
  }

  // ---------------------------------------------------------------------------

  bool _accepts(TranscriptSegmentEntity s) =>
      _sessionId != null &&
      !_paused &&
      !s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) &&
      !_dictated(s);

  bool _dictated(TranscriptSegmentEntity s) =>
      s.source == AudioSource.input &&
      _dictation.entries.any(
        (MapEntry<int, int?> r) =>
            s.timestampMs >= r.key && s.timestampMs <= (r.value ?? 1 << 62),
      );

  static String _normalized(String text) => fold(text)
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceFirst(RegExp(r'^((et|alors|donc|mais|and|so) )+'), '');

  bool _isDuplicate(String text, int atMs) {
    final String n = _normalized(text);
    return _questions.any(
      (LiveQuestion q) =>
          (q.timestampMs - atMs).abs() <=
              kQuestionDedupeWindow.inMilliseconds &&
          _normalized(q.text) == n,
    );
  }

  LiveQuestion _detect(TranscriptSegmentEntity s, String text, int? speaker) {
    final LiveQuestion q = LiveQuestion(
      id: 'q-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      sessionId: _sessionId!,
      segmentId: s.id,
      text: text,
      source: s.source,
      speaker: s.source == AudioSource.input ? null : speaker,
      timestampMs: s.timestampMs,
    );
    _questions.add(q);
    _emit();
    _guard(_store.saveDetected(q));
    return q;
  }

  void _enqueue(LiveQuestion q, {required bool manual}) {
    if (_inFlight == null) {
      unawaited(_answerQuestion(q.id, manual: manual));
    } else {
      // La plus récente gagne ; la remplacée reste « détectée ».
      _waiting = (id: q.id, manual: manual);
    }
  }

  void _next() {
    final ({String id, bool manual})? w = _waiting;
    _waiting = null;
    if (w != null && _indexOf(w.id) >= 0) {
      unawaited(_answerQuestion(w.id, manual: w.manual));
    }
  }

  Future<void> _answerQuestion(String id, {required bool manual}) async {
    final int run = ++_run;
    _inFlight = id;
    bool current() => run == _run && _indexOf(id) >= 0;
    final LiveQuestion asked = _questions[_indexOf(id)];

    // Lancée avant toute attente : budget compté dès la détection.
    final Future<List<DocumentExcerpt>> excerpts = _excerpts(asked.text);

    final LiveAnswerModel? model;
    try {
      model = await _resolveModel();
    } on Object catch (e) {
      if (current()) _fail(id, e, null);
      return;
    }
    if (!current()) return;
    if (model == null) {
      return _settle(id, (LiveQuestion q) {
        return q.copyWith(status: LiveQuestionStatus.needsModel);
      }, save: false);
    }
    if (model.isLocal && !manual && !kAutoAnswerWithLocalModel) {
      return _settle(id, (LiveQuestion q) {
        return q.copyWith(status: LiveQuestionStatus.detected, onDemand: true);
      }, save: false);
    }
    final LiveAnswerModel m = model;
    _put(
      _questions[_indexOf(id)].copyWith(
        status: LiveQuestionStatus.answering,
        answer: '',
        failure: null,
        onDemand: false,
        model: m.modelId,
      ),
    );

    final List<DocumentExcerpt> found = await excerpts;
    if (!current()) return;
    final LlmChatRequest request = buildLiveAnswerRequest(
      question: asked.text,
      asked: _lineOf(asked),
      context: _contextFor(asked),
      excerpts: found,
    );
    final StringBuffer raw = StringBuffer();
    _answer = m.provider
        .streamChat(request)
        .listen(
          (String delta) {
            raw.write(delta);
            _put(_questions[_indexOf(id)].copyWith(answer: _visible('$raw')));
          },
          onError: (Object e) => _fail(id, e, m.modelId),
          onDone: () => _complete(id, '$raw', found, m.modelId),
          cancelOnError: true,
        );
  }

  Future<List<DocumentExcerpt>> _excerpts(String question) =>
      _search(question, limit: kMaxExcerpts)
          .then((List<DocumentExcerpt> e) => e.take(kMaxExcerpts).toList())
          .timeout(kDocumentSearchBudget, onTimeout: () => <DocumentExcerpt>[])
          .catchError((Object e) {
            _log.warning('Recherche de documents échouée : $e');
            return <DocumentExcerpt>[];
          });

  /// Texte partiel affichable : le jeton réservé ne s'affiche jamais, même
  /// en partie.
  static String _visible(String raw) {
    final String t = raw.trimLeft();
    if (t.startsWith(kNoAnswerToken) || kNoAnswerToken.startsWith(t)) {
      return '';
    }
    return raw;
  }

  void _complete(
    String id,
    String raw,
    List<DocumentExcerpt> excerpts,
    String model,
  ) {
    final ParsedAnswer a = parseAnswer(raw, excerpts);
    if (!a.declined && a.text.isEmpty) {
      // Flux fini sans texte (réflexion qui a tout pris, réponse vide).
      return _fail(id, const LlmMalformedAnswerException(), model);
    }
    _settle(
      id,
      (LiveQuestion q) => q.copyWith(
        status: a.declined
            ? LiveQuestionStatus.declined
            : LiveQuestionStatus.answered,
        answer: a.text,
        truncated: a.truncated,
        sources: a.sources,
        failure: null,
        model: model,
      ),
    );
  }

  void _fail(String id, Object error, String? model) {
    _log.warning('Réponse en direct échouée : $error');
    _settle(
      id,
      (LiveQuestion q) => q.copyWith(
        status: LiveQuestionStatus.failed,
        answer: '',
        failure: _failureOf(error),
        model: model,
      ),
    );
  }

  static LiveAnswerFailure _failureOf(Object error) => switch (error) {
    LlmInvalidKeyException() => LiveAnswerFailure.invalidKey,
    LlmRateLimitedException() => LiveAnswerFailure.rateLimited,
    LlmUnreachableException() => LiveAnswerFailure.unreachable,
    LlmMalformedAnswerException() ||
    FormatException() => LiveAnswerFailure.malformed,
    _ => LiveAnswerFailure.other,
  };

  /// État final de la question en vol, puis la suivante.
  void _settle(
    String id,
    LiveQuestion Function(LiveQuestion) change, {
    bool save = true,
  }) {
    final int i = _indexOf(id);
    if (i >= 0) {
      final LiveQuestion q = change(_questions[i]);
      _put(q);
      if (save) _guard(_store.saveAnswer(q));
    }
    _answer = null;
    _inFlight = null;
    _next();
  }

  void _cancelAnswer({bool keepWaiting = false}) {
    _run++;
    unawaited(_answer?.cancel());
    _answer = null;
    _inFlight = null;
    if (!keepWaiting) _waiting = null;
  }

  ContextLine _lineOf(LiveQuestion q) => (
    source: q.source,
    speaker: q.speaker,
    timestampMs: q.timestampMs,
    text: q.text,
  );

  /// Ce qui a été dit dans [kContextWindow] jusqu'à [q], borné à
  /// [kMaxContextChars] en gardant le plus récent.
  List<ContextLine> _contextFor(LiveQuestion q) {
    final int from = q.timestampMs - kContextWindow.inMilliseconds;
    final List<ContextLine> kept = <ContextLine>[];
    int chars = 0;
    final List<_Line> ordered = List<_Line>.of(_context)
      ..sort(
        (_Line a, _Line b) =>
            a.segment.timestampMs.compareTo(b.segment.timestampMs),
      );
    for (final _Line l in ordered.reversed) {
      if (l.segment.timestampMs > q.timestampMs) continue;
      if (l.segment.timestampMs < from) break;
      final ContextLine c = (
        source: l.segment.source,
        speaker: l.speaker,
        timestampMs: l.segment.timestampMs,
        text: l.segment.text,
      );
      chars += contextLine(c).length + 1;
      if (chars > kMaxContextChars) break;
      kept.add(c);
    }
    return kept.reversed.toList();
  }

  int _indexOf(String id) =>
      _questions.indexWhere((LiveQuestion q) => q.id == id);

  void _put(LiveQuestion q) {
    final int i = _indexOf(q.id);
    if (i < 0) return;
    _questions[i] = q;
    _emit();
  }

  void _emit() => _subject.add(List<LiveQuestion>.unmodifiable(_questions));

  void _guard(Future<void> write) => unawaited(
    write.catchError((Object e) {
      _log.warning('Sauvegarde de question échouée : $e');
    }),
  );
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (int i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
