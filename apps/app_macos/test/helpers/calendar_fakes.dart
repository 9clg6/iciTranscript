import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Faux côté Swift des canaux de la tranche T5 (agenda, détection de
// réunion). Ils répondent au contrat que les specs fixent ; aucun accès au
// vrai agenda ni au vrai micro.
//
// Canal `com.icitranscript/calendar` (MethodChannel, EventKit côté Swift) :
// - `accessStatus` → String : `notDetermined` | `fullAccess` | `writeOnly` |
//   `denied` | `restricted` ;
// - `requestAccess` → même String (affiche l'invite système la 1re fois) ;
// - `calendars` → `List<Map>` `{id: String, title: String}` ;
// - `events` `{from: int, to: int (ms epoch), calendarIds: List<String>?}`
//   (null = tous les agendas) → `List<Map>` :
//   `{id: String (unique par occurrence), title: String, start: int, end: int
//   (ms epoch), allDay: bool, declined: bool, calendarId: String,
//   calendarTitle: String, attendees: List<String>}` ; `attendees` = noms
//   (EKParticipant.name, qui peut être une adresse e-mail faute de nom), un
//   par participant, organisateur compris ;
// - `openPrivacySettings` → null (ouvre Réglages Système › Calendriers) ;
// - Swift → Dart : `changed` (sans argument) sur EKEventStoreChanged.
//
// Canal `com.icitranscript/meeting_detection` (MethodChannel) :
// - `start` → bool : true si la surveillance du micro tourne (macOS 14+),
//   false si non prise en charge (macOS < 14) ;
// - `stop` → null ;
// - Swift → Dart : `micUsers` `{bundleIds: List<String>}` = instantané des
//   AUTRES processus qui tiennent l'entrée audio, envoyé à chaque changement
//   (liste vide = plus personne).

const String kCalendarChannel = 'com.icitranscript/calendar';
const String kMeetingChannel = 'com.icitranscript/meeting_detection';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<void> _fromSwift(String channel, String method, [Object? args]) async {
  await _messenger.handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (ByteData? _) {},
  );
}

/// Événement au format du canal (heures locales converties en ms epoch).
Map<String, Object?> eventJson({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  bool declined = false,
  String calendarId = 'work',
  String calendarTitle = 'Travail',
  List<String> attendees = const <String>[],
}) => <String, Object?>{
  'id': id,
  'title': title,
  'start': start.millisecondsSinceEpoch,
  'end': end.millisecondsSinceEpoch,
  'allDay': allDay,
  'declined': declined,
  'calendarId': calendarId,
  'calendarTitle': calendarTitle,
  'attendees': attendees,
};

/// Agenda macOS factice derrière `com.icitranscript/calendar`.
class FakeCalendarPlatform {
  FakeCalendarPlatform({
    this.status = 'notDetermined',
    this.afterRequest = 'fullAccess',
    List<Map<String, Object?>>? calendars,
    List<Map<String, Object?>>? events,
  }) : calendars =
           calendars ??
           <Map<String, Object?>>[
             <String, Object?>{'id': 'work', 'title': 'Travail'},
             <String, Object?>{'id': 'home', 'title': 'Perso'},
           ],
       events = events ?? <Map<String, Object?>>[];

  /// Réponse de `accessStatus`.
  String status;

  /// Statut après `requestAccess` (devient aussi [status]).
  String afterRequest;

  List<Map<String, Object?>> calendars;

  /// Tous les événements connus ; `events` renvoie ceux qui chevauchent
  /// la plage demandée et appartiennent aux agendas demandés.
  List<Map<String, Object?>> events;

  /// Si non null, `events` échoue avec ce code.
  String? eventsErrorCode;

  final List<MethodCall> calls = <MethodCall>[];

  List<MethodCall> callsTo(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();

  /// Appels qui lisent des données (pas le simple statut d'autorisation).
  List<MethodCall> get dataReads => calls
      .where(
        (MethodCall c) => const <String>{
          'requestAccess',
          'calendars',
          'events',
        }.contains(c.method),
      )
      .toList();

  void install() {
    _messenger.setMockMethodCallHandler(const MethodChannel(kCalendarChannel), (
      MethodCall call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'accessStatus':
          return status;
        case 'requestAccess':
          status = afterRequest;
          return status;
        case 'calendars':
          return calendars;
        case 'events':
          if (eventsErrorCode != null) {
            throw PlatformException(code: eventsErrorCode!);
          }
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final int from = args['from']! as int;
          final int to = args['to']! as int;
          final List<Object?>? ids = args['calendarIds'] as List<Object?>?;
          return events
              .where(
                (Map<String, Object?> e) =>
                    (e['end']! as int) > from &&
                    (e['start']! as int) < to &&
                    (ids == null || ids.contains(e['calendarId'])),
              )
              .toList();
        case 'openPrivacySettings':
          return null;
      }
      return null;
    });
    addTearDown(
      () => _messenger.setMockMethodCallHandler(
        const MethodChannel(kCalendarChannel),
        null,
      ),
    );
  }

  /// Swift signale un changement du magasin d'événements.
  Future<void> notifyChanged() => _fromSwift(kCalendarChannel, 'changed');
}

/// Surveillance du micro factice derrière `com.icitranscript/meeting_detection`.
class FakeMeetingPlatform {
  FakeMeetingPlatform({this.supported = true});

  /// Réponse de `start` (false = macOS < 14).
  bool supported;

  final List<MethodCall> calls = <MethodCall>[];

  void install() {
    _messenger.setMockMethodCallHandler(const MethodChannel(kMeetingChannel), (
      MethodCall call,
    ) async {
      calls.add(call);
      if (call.method == 'start') return supported;
      return null;
    });
    addTearDown(
      () => _messenger.setMockMethodCallHandler(
        const MethodChannel(kMeetingChannel),
        null,
      ),
    );
  }

  /// Swift envoie l'instantané des autres processus qui tiennent le micro.
  Future<void> micUsers(List<String> bundleIds) => _fromSwift(
    kMeetingChannel,
    'micUsers',
    <String, Object?>{'bundleIds': bundleIds},
  );
}

/// Horloge des tests de widgets : [anchor] + temps simulé écoulé (avance
/// avec `tester.pump(durée)`). À passer en override de `nowProvider`.
DateTime Function() widgetClock(WidgetTester tester, DateTime anchor) {
  final DateTime origin = tester.binding.clock.now();
  return () => anchor.add(tester.binding.clock.now().difference(origin));
}
