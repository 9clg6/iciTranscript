import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// « Coach anglais » et « Interlocuteurs en direct » survivent à un
/// redémarrage (prefs.json) et sont lus par le view model du direct à son
/// démarrage (besoin 7). Par défaut : coach coupé, interlocuteurs actifs
/// (valeurs d'aujourd'hui).
///
/// Vrai LiveTranscriptionViewModel ; serveur, micro et socket factices.
/// Un conteneur = un lancement de l'app.
void main() {
  setUp(resetPrefs);

  List<Override> overrides() {
    final LiveServiceHarness harness = LiveServiceHarness(FakeAsync());
    return <Override>[
      liveTranscriptionServiceProvider.overrideWithValue(harness.service),
      processManagerServiceProvider.overrideWithValue(
        ProcessManagerService(channel: FakeProcessManagerChannel()),
      ),
      audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
    ];
  }

  ProviderContainer launch() {
    final ProviderContainer c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c.read(liveTranscriptionViewModelProvider);
    return c;
  }

  LiveTranscriptionState live(ProviderContainer c) =>
      c.read(liveTranscriptionViewModelProvider);
  LiveTranscriptionViewModel liveVm(ProviderContainer c) =>
      c.read(liveTranscriptionViewModelProvider.notifier);

  test('sans prefs.json : coach coupé, interlocuteurs actifs', () async {
    final ProviderContainer c = launch();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(live(c).isCoachEnabled, isFalse);
    expect(live(c).isLiveSpeakersEnabled, isTrue);
  });

  test('coach activé : toujours activé au lancement suivant', () async {
    final ProviderContainer first = launch();
    liveVm(first).toggleCoach();
    expect(live(first).isCoachEnabled, isTrue);
    await eventually(() => expect(prefsFile.existsSync(), isTrue));

    final ProviderContainer again = launch();
    await eventually(() => expect(live(again).isCoachEnabled, isTrue));
  });

  test('interlocuteurs coupés : toujours coupés au lancement suivant',
      () async {
    final ProviderContainer first = launch();
    liveVm(first).toggleLiveSpeakers();
    expect(live(first).isLiveSpeakersEnabled, isFalse);
    await eventually(() => expect(prefsFile.existsSync(), isTrue));

    final ProviderContainer again = launch();
    await eventually(
      () => expect(live(again).isLiveSpeakersEnabled, isFalse),
    );
  });

  test('aller-retour : le dernier état gagne', () async {
    final ProviderContainer first = launch();
    liveVm(first)
      ..toggleCoach()
      ..toggleCoach()
      ..toggleCoach();
    expect(live(first).isCoachEnabled, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final ProviderContainer again = launch();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(live(again).isCoachEnabled, isTrue);
  });

  test('prefs.json abîmé : le direct démarre avec les valeurs par défaut',
      () async {
    prefsFile.parent.createSync(recursive: true);
    prefsFile.writeAsStringSync('{"coach_enab');

    final ProviderContainer c = launch();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(live(c).isCoachEnabled, isFalse);
    expect(live(c).isLiveSpeakersEnabled, isTrue);
  });

  group('deux écrivains (Réglages et direct) dans le même lancement', () {
    test('micro choisi et coach activé ensemble : les deux survivent',
        () async {
      final ProviderContainer c = launch();
      final SettingsViewModel settings = c.read(
        settingsViewModelProvider.notifier,
      );
      await eventually(
        () => expect(c.read(settingsViewModelProvider).storagePath, isNotEmpty),
      );

      final Future<void> mic = settings.updateMic('mic-2');
      liveVm(c).toggleCoach();
      await mic;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final ProviderContainer again = launch();
      again.read(settingsViewModelProvider);
      await eventually(() {
        expect(live(again).isCoachEnabled, isTrue);
        expect(again.read(settingsViewModelProvider).selectedMicId, 'mic-2');
      });
    });

    test('les clés écrites par une autre partie de l\'app restent', () async {
      prefsFile.parent.createSync(recursive: true);
      prefsFile.writeAsStringSync(
        jsonEncode(<String, Object?>{'dictation_shortcut': 'cmd+shift+d'}),
      );

      final ProviderContainer c = launch();
      liveVm(c).toggleLiveSpeakers();

      await eventually(() {
        final Map<String, dynamic> prefs = readPrefs();
        expect(prefs['dictation_shortcut'], 'cmd+shift+d');
        expect(prefs.length, greaterThan(1), reason: 'interrupteur écrit');
      });
    });
  });
}
