import 'package:core_domain/domain/services/session_history.service.dart';
import 'package:core_domain/domain/usecases/delete_session.use_case.dart';
import 'package:core_domain/domain/usecases/get_session_detail.use_case.dart';
import 'package:core_domain/domain/usecases/get_sessions.use_case.dart';
import 'package:core_domain/domain/usecases/update_session_title.use_case.dart';
import 'package:ici_transcript/core/providers/core/usecases/delete_session.use_case.provider.dart';
import 'package:ici_transcript/core/providers/core/usecases/get_session_detail.use_case.provider.dart';
import 'package:ici_transcript/core/providers/core/usecases/get_sessions.use_case.provider.dart';
import 'package:ici_transcript/core/providers/core/usecases/update_session_title.use_case.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_history.service.provider.g.dart';

/// Provider pour [SessionHistoryService].
///
/// Orchestre l'historique des sessions : chargement de la liste,
/// detail d'une session, suppression, modification du titre.
@riverpod
SessionHistoryService sessionHistoryService(Ref ref) {
  final GetSessionsUseCase getSessionsUseCase = ref.watch(
    getSessionsUseCaseProvider,
  );
  final GetSessionDetailUseCase getSessionDetailUseCase = ref.watch(
    getSessionDetailUseCaseProvider,
  );
  final DeleteSessionUseCase deleteSessionUseCase = ref.watch(
    deleteSessionUseCaseProvider,
  );
  final UpdateSessionTitleUseCase updateSessionTitleUseCase = ref.watch(
    updateSessionTitleUseCaseProvider,
  );

  final SessionHistoryService service = SessionHistoryService(
    getSessionsUseCase: getSessionsUseCase,
    getSessionDetailUseCase: getSessionDetailUseCase,
    deleteSessionUseCase: deleteSessionUseCase,
    updateSessionTitleUseCase: updateSessionTitleUseCase,
  );

  ref.onDispose(service.dispose);
  return service;
}
