import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/live_answers_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

// Panneau de barre de menus (T3), besoin 4 : fermer la fenêtre principale
// n'arrête pas une note. Côté Dart, l'enregistrement ne dépend pas du cycle
// de vie de la fenêtre : la fenêtre masquée (inactive → hidden → paused),
// la capture continue, les phrases continuent d'arriver.
//
// Vert aujourd'hui : épingle que personne n'ajoute un arrêt sur le cycle de
// vie. Le reste ne se vérifie qu'en natif (AppDelegate.swift :
// `applicationShouldTerminateAfterLastWindowClosed` renvoie true
// aujourd'hui ; il doit renvoyer false et la fermeture masquer la fenêtre).
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fenêtre masquée pendant une note : l\'enregistrement continue',
    () async {
      resetPrefs();
      final LiveServiceHarness live = LiveServiceHarness(FakeAsync());
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          liveTranscriptionServiceProvider.overrideWithValue(live.service),
          processManagerServiceProvider.overrideWithValue(
            ProcessManagerService(channel: live.process),
          ),
          audioCaptureChannelProvider.overrideWithValue(live.audio),
          apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
          databaseProvider.overrideWithValue(memoryDatabase()),
          liveAnswersServiceProvider.overrideWithValue(
            LiveAnswersHarness().service,
          ),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(() => live.service.stopTranscription());
      addTearDown(() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });

      c.read(liveTranscriptionViewModelProvider.notifier);
      await c.read(liveTranscriptionViewModelProvider.notifier).startSession();
      expect(c.read(liveTranscriptionViewModelProvider).isRecording, isTrue);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      live.fakeRemote.emitDone(AudioSource.output, 'On continue sans fenêtre.');
      await eventually(
        () => expect(
          c
              .read(liveTranscriptionViewModelProvider)
              .segments
              .map((TranscriptSegmentEntity s) => s.text),
          contains('On continue sans fenêtre.'),
        ),
      );
      expect(c.read(liveTranscriptionViewModelProvider).isRecording, isTrue);
      expect(live.audio.stopCalls, 0);
      expect(live.service.isRecording, isTrue);
    },
  );
}
