import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/services/session_history.service.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_list.view_model.g.dart';

/// ViewModel de la liste des sessions (sidebar).
///
/// Ecoute le [SessionHistoryService] pour charger et filtrer
/// les sessions, gerer la selection et la suppression.
@riverpod
class SessionListViewModel extends _$SessionListViewModel {
  late SessionHistoryService _sessionHistoryService;

  @override
  SessionListState build() {
    _sessionHistoryService = ref.watch(sessionHistoryServiceProvider);
    _init();
    return SessionListState.initial();
  }

  Future<void> _init() async {
    await _sessionHistoryService.loadSessions();
    _sessionHistoryService.sessionsStream.listen((
      List<SessionEntity> sessions,
    ) {
      state = state.copyWith(sessions: sessions);
    });
  }

  /// Selectionne une session par son identifiant.
  void selectSession(String id) {
    state = state.copyWith(selectedSessionId: id);
  }

  /// Désélectionne la session courante.
  void clearSelection() {
    state = state.copyWith(selectedSessionId: null);
  }

  /// Supprime une session par son identifiant.
  Future<void> deleteSession(String id) async {
    await _sessionHistoryService.deleteSession(id);
    // Remove from local state immediately.
    final List<SessionEntity> updatedSessions = state.sessions
        .where((SessionEntity s) => s.id != id)
        .toList();
    state = state.copyWith(
      sessions: updatedSessions,
      selectedSessionId: state.selectedSessionId == id
          ? null
          : state.selectedSessionId,
    );
  }

  /// Filtre les sessions par requete de recherche.
  void search(String query) {
    state = state.copyWith(searchQuery: query);
  }
}
