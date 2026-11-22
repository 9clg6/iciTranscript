import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/now.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/settings_fakes.dart';

// T5, besoin 3 : démarrer une note (« Nouvelle note », « Démarrer la note »
// d'un événement ou d'une suggestion : tous passent par
// LiveTranscriptionViewModel.startSession()) la lie à l'événement en cours
// ou qui commence dans 5 minutes : `calendarEventId`, titre de la note = titre
// de l'événement, `attendees` = noms des participants (sans adresse e-mail).
// Sinon, aucun lien. Agenda non connecté ou accès retiré : aucun lien et
// aucune lecture de l'agenda.
//
// Vrai LiveTranscriptionViewModel ; serveur, micro et socket factices
// (LiveServiceHarness), agenda factice derrière le canal, prefs.json du
// dossier temporaire des tests.
//
// API supposée :
// - `nowProvider` (lib/core/providers/platform/now.provider.dart,
//   `@Riverpod(keepAlive: true) DateTime Function() now(Ref ref)`, défaut
//   `DateTime.now`) : seule horloge de l'agenda et de la détection ;
// - prefs.json : `calendar_connected` (bool, absent = false),
//   `calendar_ids` (List<String>, absent = tous les agendas) ;
// - SessionEntity.calendarEventId / calendarEventTitle / attendees.
final DateTime _now = DateTime(2026, 11, 23, 10);

void _writePrefs(Map<String, Object?> prefs) {
  prefsFile.parent.createSync(recursive: true);
  prefsFile.writeAsStringSync(jsonEncode(prefs));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPrefs);

  late LiveServiceHarness harness;

  Future<SessionEntity> startNote() async {
    harness = LiveServiceHarness(FakeAsync());
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(harness.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: harness.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        nowProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(c.dispose);
    c.read(liveTranscriptionViewModelProvider);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    unawaited(
      c.read(liveTranscriptionViewModelProvider.notifier).startSession(),
    );
    await eventually(() => expect(harness.sessions.store.values, hasLength(1)));
    // Laisse le temps au lien de s'écrire.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return harness.sessions.store.values.single;
  }

  Map<String, Object?> comite({
    DateTime? start,
    Duration length = const Duration(hours: 1),
    String calendarId = 'work',
  }) {
    final DateTime s = start ?? _now.subtract(const Duration(minutes: 10));
    return eventJson(
      id: 'evt-comite',
      title: 'Comité produit',
      start: s,
      end: s.add(length),
      calendarId: calendarId,
      attendees: <String>['Alice Martin', 'bob@example.com', 'Chloé Durand'],
    );
  }

  test('pendant un événement en cours : la note est liée, prend son titre '
      'et les noms des participants', () async {
    _writePrefs(<String, Object?>{'calendar_connected': true});
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[comite()],
    ).install();

    final SessionEntity s = await startNote();

    expect(s.calendarEventId, 'evt-comite');
    expect(s.calendarEventTitle, 'Comité produit');
    expect(s.title, 'Comité produit');
    expect(s.attendees, <String>['Alice Martin', 'Chloé Durand']);
  });

  test('un événement qui commence dans 4 minutes : liée', () async {
    _writePrefs(<String, Object?>{'calendar_connected': true});
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[
        comite(start: _now.add(const Duration(minutes: 4))),
      ],
    ).install();

    expect((await startNote()).calendarEventId, 'evt-comite');
  });

  test('aucun événement proche : pas de lien, titre par défaut', () async {
    _writePrefs(<String, Object?>{'calendar_connected': true});
    FakeCalendarPlatform(
      status: 'fullAccess',
      events: <Map<String, Object?>>[
        comite(start: _now.add(const Duration(hours: 2))),
      ],
    ).install();

    final SessionEntity s = await startNote();

    expect(s.calendarEventId, isNull);
    expect(s.calendarEventTitle, isNull);
    expect(s.attendees, isEmpty);
    expect(s.title, isNot('Comité produit'));
  });

  test(
    'agenda jamais connecté : pas de lien, rien lu dans l\'agenda',
    () async {
      final FakeCalendarPlatform platform = FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[comite()],
      )..install();

      final SessionEntity s = await startNote();

      expect(s.calendarEventId, isNull);
      expect(platform.dataReads, isEmpty);
    },
  );

  test('connecté puis accès retiré dans Réglages Système : pas de lien, '
      'aucun événement lu', () async {
    _writePrefs(<String, Object?>{'calendar_connected': true});
    final FakeCalendarPlatform platform = FakeCalendarPlatform(
      status: 'denied',
      events: <Map<String, Object?>>[comite()],
    )..install();

    final SessionEntity s = await startNote();

    expect(s.calendarEventId, isNull);
    expect(platform.callsTo('events'), isEmpty);
  });

  test(
    'un événement d\'un agenda exclu dans Réglages n\'est pas lié',
    () async {
      _writePrefs(<String, Object?>{
        'calendar_connected': true,
        'calendar_ids': <String>['home'],
      });
      FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[comite(calendarId: 'work')],
      ).install();

      expect((await startNote()).calendarEventId, isNull);
    },
  );

  test(
    'ni le titre ni les participants ne sont écrits dans le journal',
    () async {
      final Directory dir = Directory.systemTemp.createTempSync('oats-log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String path = '${dir.path}/oats.log';
      Log.writeToFile(path);
      _writePrefs(<String, Object?>{'calendar_connected': true});
      FakeCalendarPlatform(
        status: 'fullAccess',
        events: <Map<String, Object?>>[comite()],
      ).install();

      final SessionEntity s = await startNote();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(s.calendarEventId, 'evt-comite', reason: 'le lien a bien eu lieu');
      final String log = File(path).readAsStringSync();
      expect(log, contains('startSession'), reason: 'le journal est capté');
      expect(log, isNot(contains('Comité produit')));
      expect(log, isNot(contains('Alice')));
      expect(log, isNot(contains('Chloé')));
      expect(log, isNot(contains('bob@example.com')));
    },
  );
}
