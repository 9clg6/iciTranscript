import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/session_calendar_link.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_foundation/interfaces/future.usecases.dart';
import 'package:core_foundation/interfaces/results.usecases.dart';

/// Demarre une nouvelle session de transcription.
final class StartSessionUseCase extends FutureUseCase<SessionEntity> {
  /// Cree une instance de [StartSessionUseCase].
  StartSessionUseCase({required SessionRepository sessionRepository})
    : _sessionRepository = sessionRepository;

  final SessionRepository _sessionRepository;

  /// Comme [execute], la note étant liée à [link] (titre compris).
  Future<ResultState<SessionEntity>> executeLinked(
    SessionCalendarLink? link,
  ) async {
    try {
      return ResultState<SessionEntity>.success(
        await invoke(link).timeout(const Duration(seconds: 15)),
      );
    } on Exception catch (e) {
      return ResultState<SessionEntity>.failure(e);
    }
  }

  @override
  Future<SessionEntity> invoke([SessionCalendarLink? link]) {
    final DateTime now = DateTime.now();
    final SessionEntity session = SessionEntity(
      id: now.millisecondsSinceEpoch.toString(),
      title:
          link?.eventTitle ??
          'Session ${now.toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
      createdAt: now,
      updatedAt: now,
      status: SessionStatus.active,
      calendarEventId: link?.eventId,
      calendarEventTitle: link?.eventTitle,
      attendees: link?.attendees ?? const <String>[],
    );
    return _sessionRepository.create(session);
  }
}
