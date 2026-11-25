import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/services/session_history.service.dart';
import 'package:core_domain/domain/usecases/get_session_detail.use_case.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/application/services/summary.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/core/providers/services/question_store.provider.dart';
import 'package:ici_transcript/core/providers/services/ready_llm.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/shared/presentation/llm_error_key.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_detail.view_model.g.dart';

/// ViewModel de l'ecran de detail d'une session.
///
/// Charge la session et ses segments, gere l'edition du titre,
/// la suppression, l'export, la copie, ainsi que la generation a la demande
/// du resume IA et du retour du coach d'anglais.
@riverpod
class SessionDetailViewModel extends _$SessionDetailViewModel {
  late SessionHistoryService _sessionHistoryService;
  late SummaryService _summaryService;
  final Log _log = Log.named('SessionDetailViewModel');

  @override
  Future<SessionDetailState> build({required String sessionId}) async {
    _sessionHistoryService = ref.watch(sessionHistoryServiceProvider);
    _summaryService = ref.watch(summaryServiceProvider);
    return _loadSession(sessionId);
  }

  Future<SessionDetailState> _loadSession(String sessionId) async {
    final SessionDetailResult? detail = await _sessionHistoryService
        .getSessionDetail(sessionId);
    if (detail == null) {
      return SessionDetailState.initial();
    }
    final String? stored = await _summaryService.getSummaryForSession(
      sessionId,
    );
    final SessionAnalysis analysis = SessionAnalysis.fromStored(stored);
    return SessionDetailState(
      llmAvailable: await _llmAvailable(),
      session: detail.session,
      segments: detail.segments,
      summary: analysis.summary,
      feedback: analysis.feedback,
      speakers: analysis.speakers,
      questions: await _questions(sessionId),
    );
  }

  /// Questions gardées avec la note ; illisibles : aucune (la note s'ouvre).
  Future<List<LiveQuestion>> _questions(String sessionId) async {
    try {
      return await ref.read(questionStoreProvider).forSession(sessionId);
    } on Object catch (e) {
      _log.warning('Questions de la note illisibles : $e');
      return const <LiveQuestion>[];
    }
  }

  /// Un fournisseur peut-il repondre ? Detection seule (rien ne demarre).
  Future<bool> _llmAvailable() async {
    try {
      return await readyLlm(ref, start: false) != null;
    } on Object {
      return false;
    }
  }

  /// Met a jour le titre de la session.
  Future<void> updateTitle(String newTitle) async {
    final SessionDetailState currentState =
        state.value ?? SessionDetailState.initial();
    final SessionEntity? session = currentState.session;
    if (session == null) return;

    await _sessionHistoryService.updateSessionTitle(
      sessionId: session.id,
      newTitle: newTitle,
    );

    state = AsyncData<SessionDetailState>(
      currentState.copyWith(
        session: session.copyWith(title: newTitle),
        isEditing: false,
      ),
    );
  }

  /// Lie la note à [event] (elle prend son titre et les noms de ses
  /// participants) ou, si null, retire le lien en gardant le titre.
  Future<void> setCalendarLink(CalendarEvent? event) async {
    final SessionDetailState current =
        state.value ?? SessionDetailState.initial();
    final SessionEntity? session = current.session;
    if (session == null) return;
    final SessionEntity next = event == null
        ? session.copyWith(
            calendarEventId: null,
            calendarEventTitle: null,
            attendees: const <String>[],
          )
        : session.copyWith(
            title: event.title,
            calendarEventId: event.id,
            calendarEventTitle: event.title,
            attendees: event.attendeeNames,
          );
    await ref.read(sessionRepositoryProvider).update(next);
    await _sessionHistoryService.loadSessions();
    state = AsyncData<SessionDetailState>(current.copyWith(session: next));
  }

  /// Supprime la session courante.
  Future<void> deleteSession() async {
    final SessionEntity? session = state.value?.session;
    if (session == null) return;
    await _sessionHistoryService.deleteSession(session.id);
  }

  /// Exporte la transcription en Markdown.
  String exportMarkdown() {
    final SessionDetailState currentState =
        state.value ?? SessionDetailState.initial();
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('# ${currentState.session?.title ?? ""}');
    buffer.writeln();
    for (final TranscriptSegmentEntity segment in currentState.segments) {
      buffer.writeln(TranscriptFormatter.markdownLine(segment));
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Copie la transcription complete dans le presse-papier.
  String copyToClipboard() {
    final SessionDetailState currentState =
        state.value ?? SessionDetailState.initial();
    return _transcript(currentState);
  }

  /// Genere (a la demande) un resume IA en francais de la session, par le
  /// fournisseur actif ; le texte s'affiche au fil de l'eau.
  ///
  /// Rien d'utilisable : rien n'est envoye ni telecharge (invite de la
  /// note). Erreur : message, rien range. Reponse qui semble coupee :
  /// affichee et signalee, pas rangee comme un resume complet.
  Future<void> generateSummary() async {
    final SessionDetailState? current = state.value;
    final SessionEntity? session = current?.session;
    if (current == null || session == null || current.isSummaryLoading) return;

    final String transcript = _transcript(current);
    if (transcript.trim().isEmpty) return;

    _set(
      (SessionDetailState s) => s.copyWith(
        isSummaryLoading: true,
        summaryError: null,
        summaryIncomplete: false,
      ),
    );
    try {
      final ReadyLlm? ready = await readyLlm(ref);
      if (ready == null) {
        return _set(
          (SessionDetailState s) =>
              s.copyWith(isSummaryLoading: false, llmAvailable: false),
        );
      }
      final StringBuffer text = StringBuffer();
      await for (final String chunk in summarizeMeeting(
        ready.llm,
        transcript,
      )) {
        if (!ref.mounted) return;
        text.write(chunk);
        _set((SessionDetailState s) => s.copyWith(summary: text.toString()));
      }
      final String summary = text.toString();
      final bool incomplete = looksTruncated(summary);
      if (!incomplete) {
        await _store(
          session.id,
          (SessionAnalysis a) => a.copyWith(summary: summary),
          model: ready.model,
        );
      }
      _set(
        (SessionDetailState s) => s.copyWith(
          summary: summary,
          summaryIncomplete: incomplete,
          isSummaryLoading: false,
        ),
      );
    } on Object catch (e) {
      _log.error('Résumé échoué : $e');
      _set(
        (SessionDetailState s) => s.copyWith(
          summary: current.summary,
          summaryError: llmErrorKey(e),
          isSummaryLoading: false,
        ),
      );
    }
  }

  /// Analyse (a la demande) l'anglais parle de la session, par le
  /// fournisseur actif : phrases anglaises du micro, par lots ; un lot en
  /// échec est rangé « non analysé » (la note propose de réessayer).
  Future<void> analyzeEnglish() => _coach(
    (SessionDetailState s) => s.segments,
    (EnglishFeedbackEntity? old, EnglishFeedbackEntity found) => found,
  );

  /// « Réessayer » : seules les phrases non analysées repartent ; leurs
  /// corrections s'ajoutent à celles déjà là.
  Future<void> retryUnanalyzed() => _coach(
    (SessionDetailState s) {
      final Set<String> ids =
          s.feedback?.unanalyzedSegmentIds.toSet() ?? const <String>{};
      return <TranscriptSegmentEntity>[
        for (final TranscriptSegmentEntity x in s.segments)
          if (ids.contains(x.id)) x,
      ];
    },
    (EnglishFeedbackEntity? old, EnglishFeedbackEntity found) => found.copyWith(
      overall: old?.overall ?? found.overall,
      corrections: mergeCorrections(
        old?.corrections ?? const <EnglishCorrectionEntity>[],
        found.corrections,
      ),
    ),
  );

  /// Coach sur les segments choisis par [pick] ; le résultat, combiné à
  /// l'ancien retour par [combine], est rangé puis affiché. Tout en échec :
  /// l'erreur est affichée, rien n'est rangé.
  Future<void> _coach(
    List<TranscriptSegmentEntity> Function(SessionDetailState s) pick,
    EnglishFeedbackEntity Function(
      EnglishFeedbackEntity? old,
      EnglishFeedbackEntity found,
    )
    combine,
  ) async {
    final SessionDetailState? current = state.value;
    final SessionEntity? session = current?.session;
    if (current == null || session == null || current.isFeedbackLoading) return;

    // Coach = phrases anglaises du micro UNIQUEMENT (pas l'audio du meeting).
    final List<TranscriptSegmentEntity> segments = pick(current);
    if (coachableLines(segments).isEmpty) {
      // Réessayer sans phrase : rien à faire. Coach sur une note sans
      // anglais de l'utilisateur : la note le dit, rien n'est envoyé.
      if (current.feedback?.unanalyzedSegmentIds.isNotEmpty ?? false) return;
      const EnglishFeedbackEntity nothing = EnglishFeedbackEntity(
        nothingToAnalyse: true,
      );
      await _store(
        session.id,
        (SessionAnalysis a) => a.copyWith(feedback: nothing),
      );
      return _set(
        (SessionDetailState s) =>
            s.copyWith(feedback: nothing, feedbackError: null),
      );
    }

    _set(
      (SessionDetailState s) =>
          s.copyWith(isFeedbackLoading: true, feedbackError: null),
    );
    try {
      final ReadyLlm? ready = await readyLlm(ref);
      if (ready == null) {
        return _set(
          (SessionDetailState s) =>
              s.copyWith(isFeedbackLoading: false, llmAvailable: false),
        );
      }
      final EnglishFeedbackEntity found = await coachMeeting(
        ready.llm,
        segments,
      );
      if (!ref.mounted) return;
      final EnglishFeedbackEntity feedback = combine(current.feedback, found);
      // Le coach garde le modele du resume deja range (pas de `model`).
      await _store(
        session.id,
        (SessionAnalysis a) => a.copyWith(feedback: feedback),
      );
      _set(
        (SessionDetailState s) =>
            s.copyWith(feedback: feedback, isFeedbackLoading: false),
      );
    } on Object catch (e) {
      _log.error('Coach anglais échoué : $e');
      _set(
        (SessionDetailState s) =>
            s.copyWith(feedbackError: llmErrorKey(e), isFeedbackLoading: false),
      );
    }
  }

  /// Supprime le resume IA de la session.
  Future<void> deleteSummary() async {
    final SessionEntity? session = state.value?.session;
    if (session == null) return;
    await _store(
      session.id,
      (SessionAnalysis a) => a.copyWith(clearSummary: true),
    );
    _set(
      (SessionDetailState s) => s.copyWith(
        summary: null,
        summaryIncomplete: false,
        summaryError: null,
      ),
    );
  }

  /// Supprime le retour du coach d'anglais de la session.
  Future<void> deleteFeedback() async {
    final SessionEntity? session = state.value?.session;
    if (session == null) return;
    await _store(
      session.id,
      (SessionAnalysis a) => a.copyWith(clearFeedback: true),
    );
    _set(
      (SessionDetailState s) => s.copyWith(feedback: null, feedbackError: null),
    );
  }

  /// Active ou desactive le mode edition du titre.
  void toggleEditing() {
    final SessionDetailState currentState =
        state.value ?? SessionDetailState.initial();
    state = AsyncData<SessionDetailState>(
      currentState.copyWith(isEditing: !currentState.isEditing),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  // Un passage non transcrit n'est la phrase de personne : il n'entre pas
  // dans le texte envoyé au modèle comme une ligne dite.
  String _transcript(SessionDetailState s) => s.segments
      .where(
        (TranscriptSegmentEntity x) =>
            !LiveTranscriptionService.isUntranscribedMarker(x.text) &&
            !LiveTranscriptionService.isNoAudioCopyMarker(x.text),
      )
      .map(TranscriptFormatter.plainLine)
      .join('\n');

  /// Range l'enveloppe stockee modifiee par [change] : on part de la base,
  /// pas de l'etat affiche (qui peut porter un resume coupe), et on garde
  /// transcription propre et interlocuteurs.
  Future<void> _store(
    String sessionId,
    SessionAnalysis Function(SessionAnalysis stored) change, {
    String? model,
  }) async {
    final SessionAnalysis next = change(
      SessionAnalysis.fromStored(
        await _summaryService.getSummaryForSession(sessionId),
      ),
    );
    if (next.isEmpty) {
      await _summaryService.deleteSummaryForSession(sessionId);
    } else {
      await _summaryService.saveSummary(
        sessionId: sessionId,
        content: next.toStored(),
        model: model,
      );
    }
  }

  /// Applique [change] a l'etat courant, si le view model vit encore.
  void _set(SessionDetailState Function(SessionDetailState s) change) {
    if (!ref.mounted) return;
    state = AsyncData<SessionDetailState>(
      change(state.value ?? SessionDetailState.initial()),
    );
  }
}
