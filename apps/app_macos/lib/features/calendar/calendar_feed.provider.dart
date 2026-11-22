import 'dart:async';

import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/core/platform/calendar_channel.dart';
import 'package:ici_transcript/core/providers/platform/calendar_channel.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_prefs.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calendar_feed.provider.g.dart';

/// Ce que l'agenda donne à lire.
sealed class CalendarFeed {
  const CalendarFeed();
}

/// L'utilisateur n'a pas connecté l'agenda : rien n'est lu.
class CalendarNotConnected extends CalendarFeed {
  /// Crée l'état.
  const CalendarNotConnected();
}

/// macOS refuse l'accès (refusé, restreint ou écriture seule).
class CalendarDenied extends CalendarFeed {
  /// Crée l'état.
  const CalendarDenied();
}

/// Événements d'aujourd'hui et de demain des agendas inclus.
class CalendarEvents extends CalendarFeed {
  /// Crée l'état.
  const CalendarEvents(this.events, {required this.day});

  /// Occurrences lues (toutes, filtrage par les règles).
  final List<CalendarEvent> events;

  /// Jour (minuit local) à partir duquel la plage a été lue.
  final DateTime day;
}

/// Minuit local du jour de [t].
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Événements de l'agenda, relus quand l'agenda change, quand le jour change
/// et quand les réglages de l'agenda changent.
@Riverpod(keepAlive: true, retry: _noRetry)
class CalendarFeedController extends _$CalendarFeedController {
  // « Connecter » refusé : montre la marche à suivre sans retenir la
  // connexion (au lancement suivant, « Connecter » revient).
  bool _requestDenied = false;

  CalendarChannel get _channel => ref.read(calendarChannelProvider);

  @override
  Future<CalendarFeed> build() async {
    final CalendarPrefs prefs = await ref.watch(
      calendarPrefsControllerProvider.future,
    );
    if (!prefs.connected) {
      return _requestDenied
          ? const CalendarDenied()
          : const CalendarNotConnected();
    }
    final DateTime Function() now = ref.watch(nowProvider);
    final DateTime day = startOfDay(now());
    final StreamSubscription<void> changes = _channel.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    // ponytail: vérifie le jour chaque minute ; un minuteur jusqu'à minuit
    // dériverait avec la mise en veille.
    final Timer dayCheck = Timer.periodic(const Duration(minutes: 1), (_) {
      if (startOfDay(now()) != day) ref.invalidateSelf();
    });
    ref.onDispose(() {
      unawaited(changes.cancel());
      dayCheck.cancel();
    });
    if (await _channel.accessStatus() != CalendarAccess.granted) {
      return const CalendarDenied();
    }
    final List<CalendarEvent> events = await _channel.events(
      from: day,
      to: DateTime(day.year, day.month, day.day + 2),
      calendarIds: prefs.calendarIds,
    );
    return CalendarEvents(events, day: day);
  }

  /// Demande l'accès (invite système la première fois) puis connecte.
  Future<void> connect() async {
    final CalendarAccess access = await _channel.requestAccess();
    _requestDenied = access != CalendarAccess.granted;
    if (_requestDenied) {
      ref.invalidateSelf();
      return;
    }
    await ref.read(calendarPrefsControllerProvider.notifier).setConnected(true);
  }

  /// Déconnecte : plus rien n'est lu.
  Future<void> disconnect() async {
    _requestDenied = false;
    await ref
        .read(calendarPrefsControllerProvider.notifier)
        .setConnected(false);
  }

  /// Ouvre Réglages Système › Calendriers.
  Future<void> openPrivacySettings() => _channel.openPrivacySettings();

  /// Relit (après une erreur).
  void retry() => ref.invalidateSelf();
}

Duration? _noRetry(int retryCount, Object error) => null;

/// Agendas de l'utilisateur (à lire seulement une fois connecté et autorisé).
@riverpod
Future<List<CalendarInfo>> calendarList(Ref ref) =>
    ref.read(calendarChannelProvider).calendars();
