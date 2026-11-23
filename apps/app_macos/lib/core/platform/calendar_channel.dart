import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';

/// Agenda macOS (EventKit, `CalendarPlugin.swift`).
///
/// Canal `com.icitranscript/calendar` : `accessStatus`, `requestAccess`,
/// `calendars`, `events {from, to (ms epoch), calendarIds (null = tous)}`,
/// `openPrivacySettings` ; Swift appelle `changed` quand le magasin
/// d'événements change.
class CalendarChannel {
  /// Crée le canal.
  const CalendarChannel();

  static const MethodChannel _channel = MethodChannel(
    'com.icitranscript/calendar',
  );

  static final StreamController<void> _changes =
      StreamController<void>.broadcast(onListen: _listenToSwift);

  static void _listenToSwift() =>
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'changed') _changes.add(null);
      });

  /// Émet quand les événements ou agendas ont changé.
  Stream<void> get changes => _changes.stream;

  /// Statut actuel, sans invite.
  Future<CalendarAccess> accessStatus() async =>
      _access(await _channel.invokeMethod<String>('accessStatus'));

  /// Affiche l'invite système la première fois ; rend le statut obtenu.
  Future<CalendarAccess> requestAccess() async =>
      _access(await _channel.invokeMethod<String>('requestAccess'));

  /// Agendas de l'utilisateur.
  Future<List<CalendarInfo>> calendars() async {
    final List<Map<Object?, Object?>>? raw = await _channel
        .invokeListMethod<Map<Object?, Object?>>('calendars');
    return <CalendarInfo>[
      for (final Map<Object?, Object?> c in raw ?? <Map<Object?, Object?>>[])
        CalendarInfo(id: c['id']! as String, title: c['title']! as String),
    ];
  }

  /// Occurrences qui chevauchent [from]–[to] dans [calendarIds] (null =
  /// tous les agendas).
  Future<List<CalendarEvent>> events({
    required DateTime from,
    required DateTime to,
    List<String>? calendarIds,
  }) async {
    final List<Map<Object?, Object?>>? raw = await _channel
        .invokeListMethod<Map<Object?, Object?>>('events', <String, Object?>{
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
          'calendarIds': calendarIds,
        });
    return (raw ?? <Map<Object?, Object?>>[]).map(_event).toList();
  }

  /// Ouvre Réglages Système › Confidentialité › Calendriers.
  Future<void> openPrivacySettings() =>
      _channel.invokeMethod<void>('openPrivacySettings');

  static CalendarAccess _access(String? raw) => switch (raw) {
    'notDetermined' => CalendarAccess.notDetermined,
    'fullAccess' => CalendarAccess.granted,
    _ => CalendarAccess.denied,
  };

  static CalendarEvent _event(Map<Object?, Object?> e) {
    final List<String> attendees =
        (e['attendees'] as List<Object?>? ?? <Object?>[])
            .whereType<String>()
            .toList();
    return CalendarEvent(
      id: e['id']! as String,
      title: e['title'] as String? ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(e['start']! as int),
      end: DateTime.fromMillisecondsSinceEpoch(e['end']! as int),
      allDay: e['allDay'] as bool? ?? false,
      declined: e['declined'] as bool? ?? false,
      calendarId: e['calendarId'] as String? ?? '',
      calendarTitle: e['calendarTitle'] as String? ?? '',
      attendeeNames: attendees.where(_isDisplayName).toList(),
      attendeeCount: attendees.length,
    );
  }

  // EventKit rend l'adresse quand le participant n'a pas de nom : on ne
  // garde jamais une adresse e-mail.
  static bool _isDisplayName(String name) =>
      name.trim().isNotEmpty && !name.contains('@');
}
