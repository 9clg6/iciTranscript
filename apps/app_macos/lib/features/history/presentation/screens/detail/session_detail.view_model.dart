import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/services/session_history.service.dart';
import 'package:core_domain/domain/usecases/get_session_detail.use_case.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/application/services/summary.service.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
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
  late OllamaService _ollamaService;

  @override
  Future<SessionDetailState> build({required String sessionId}) async {
    _sessionHistoryService = ref.watch(sessionHistoryServiceProvider);
    _summaryService = ref.watch(summaryServiceProvider);
    _ollamaService = ref.watch(ollamaServiceProvider);
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
      session: detail.session,
      segments: detail.segments,
      summary: analysis.summary,
      feedback: analysis.feedback,
      speakers: analysis.speakers,
    );
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
      buffer.writeln(
        '**[${segment.source.name.toUpperCase()}]** '
        '${segment.text}',
      );
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

  /// Genere (a la demande) un resume IA en francais de la session.
  Future<void> generateSummary() async {
    final SessionDetailState? current = state.value;
    final SessionEntity? session = current?.session;
    if (current == null || session == null || current.isSummaryLoading) return;

    final String transcript = _transcript(current);
    if (transcript.trim().isEmpty) return;

    state = AsyncData<SessionDetailState>(
      current.copyWith(isSummaryLoading: true),
    );
    try {
      await _ollamaService.ensureReady();
      final String summary = await _ollamaService.summarize(transcript);
      await _persist(session.id, summary: summary);
      _emit(summary: summary, isSummaryLoading: false);
    } catch (e) {
      _emit(
        summary: 'Erreur lors de la génération du résumé : $e',
        isSummaryLoading: false,
      );
    }
  }

  /// Analyse (a la demande) l'anglais parle de la session.
  Future<void> analyzeEnglish() async {
    final SessionDetailState? current = state.value;
    final SessionEntity? session = current?.session;
    if (current == null || session == null || current.isFeedbackLoading) return;

    // Coach = micro de l'utilisateur UNIQUEMENT (pas l'audio du meeting).
    final String transcript = _micTranscript(current);
    if (transcript.trim().isEmpty) return;

    state = AsyncData<SessionDetailState>(
      current.copyWith(isFeedbackLoading: true),
    );
    try {
      await _ollamaService.ensureReady();
      final EnglishFeedbackEntity feedback =
          await _ollamaService.analyzeEnglish(transcript);
      await _persist(session.id, feedback: feedback);
      _emit(feedback: feedback, isFeedbackLoading: false);
    } catch (e) {
      _emit(
        feedback: EnglishFeedbackEntity(overall: 'Erreur Ollama : $e'),
        isFeedbackLoading: false,
      );
    }
  }

  /// Supprime le resume IA de la session.
  Future<void> deleteSummary() async {
    final SessionEntity? session = state.value?.session;
    if (session == null) return;
    await _persist(session.id, clearSummary: true);
    _emit(clearSummary: true);
  }

  /// Supprime le retour du coach d'anglais de la session.
  Future<void> deleteFeedback() async {
    final SessionEntity? session = state.value?.session;
    if (session == null) return;
    await _persist(session.id, clearFeedback: true);
    _emit(clearFeedback: true);
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

  String _transcript(SessionDetailState s) =>
      s.segments.map((TranscriptSegmentEntity seg) => seg.text).join('\n');

  /// Transcript du micro de l'utilisateur uniquement (source input), pour le
  /// coach d'anglais : on ne corrige que ce que l'utilisateur a dit.
  String _micTranscript(SessionDetailState s) => s.segments
      .where((TranscriptSegmentEntity seg) => seg.source == AudioSource.input)
      .map((TranscriptSegmentEntity seg) => seg.text)
      .join('\n');

  /// Persiste l'enveloppe (resume + coach) en fusionnant avec l'etat courant.
  Future<void> _persist(
    String sessionId, {
    String? summary,
    EnglishFeedbackEntity? feedback,
    bool clearSummary = false,
    bool clearFeedback = false,
  }) async {
    final SessionDetailState s = state.value ?? SessionDetailState.initial();
    final SessionAnalysis analysis = SessionAnalysis(
      summary: clearSummary ? null : (summary ?? s.summary),
      feedback: clearFeedback ? null : (feedback ?? s.feedback),
    );
    if (analysis.isEmpty) {
      await _summaryService.deleteSummaryForSession(sessionId);
    } else {
      await _summaryService.saveSummary(
        sessionId: sessionId,
        content: analysis.toStored(),
      );
    }
  }

  /// Reconstruit l'etat (les copyWith freezed ne permettent pas de remettre un
  /// champ nullable a null ; on reconstruit donc explicitement).
  void _emit({
    String? summary,
    EnglishFeedbackEntity? feedback,
    bool clearSummary = false,
    bool clearFeedback = false,
    bool? isSummaryLoading,
    bool? isFeedbackLoading,
  }) {
    final SessionDetailState s = state.value ?? SessionDetailState.initial();
    state = AsyncData<SessionDetailState>(
      SessionDetailState(
        session: s.session,
        segments: s.segments,
        isEditing: s.isEditing,
        summary: clearSummary ? null : (summary ?? s.summary),
        feedback: clearFeedback ? null : (feedback ?? s.feedback),
        isSummaryLoading: isSummaryLoading ?? s.isSummaryLoading,
        isFeedbackLoading: isFeedbackLoading ?? s.isFeedbackLoading,
        speakers: s.speakers,
      ),
    );
  }
}
