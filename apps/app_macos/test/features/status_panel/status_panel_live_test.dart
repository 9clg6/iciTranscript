import 'dart:async';

import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/status_panel/status_panel_sync.provider.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) avec le VRAI view model du direct et le
// vrai LiveTranscriptionService (serveur, micro, socket factices ; le test
// joue le serveur). Ce que le panneau montre vient de l'état réel :
// - « start » du panneau démarre une vraie note, dont le titre (celui de
//   la session créée) est envoyé ;
// - les mots dictés pendant la réunion n'apparaissent jamais dans la fin
//   de la transcription du panneau (la dictée a sa propre route,
//   `beginDictation`) ;
// - « stop » du panneau arrête et sauve la note.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LiveServiceHarness live;
  late FakeStatusPanelPlatform panel;
  late ProviderContainer c;

  setUp(() {
    resetPrefs();
    panel = FakeStatusPanelPlatform()..install();
    live = LiveServiceHarness(FakeAsync());
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(live.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: live.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        databaseProvider.overrideWithValue(memoryDatabase()),
        liveAnswersServiceProvider.overrideWithValue(
          LiveAnswersHarness().service,
        ),
        sessionListViewModelProvider.overrideWith(
          () => FakeSessionListViewModel(const <SessionEntity>[]),
        ),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(() => live.service.stopTranscription());
    c.read(liveTranscriptionViewModelProvider.notifier);
    c.listen(statusPanelSyncProvider, (_, _) {});
  });

  Map<Object?, Object?> last() => panel.last;

  List<Object?> tail() => (last()['transcript']! as List<Object?>)
      .map((Object? l) => (l! as Map<Object?, Object?>)['text'])
      .toList();

  // Temps réel : borne large (cf. specs de l'agenda).
  Future<void> soon(FutureOr<void> Function() check) =>
      eventually(check, timeout: const Duration(seconds: 10));

  Future<void> startFromPanel() async {
    await soon(() => expect(panel.updates, isNotEmpty));
    await panel.send('start');
    await soon(() => expect(last()['status'], 'recording'));
  }

  test('« start » du panneau : une vraie note démarre, son titre est '
      'envoyé', () async {
    await startFromPanel();

    await soon(() {
      expect(live.sessions.store.values, hasLength(1));
      expect(last()['title'], live.sessions.store.values.single.title);
    });
    expect(last()['title'], isNotNull);
  });

  test(
    'une phrase finie des autres arrive dans la fin de la transcription',
    () async {
      await startFromPanel();

      live.fakeRemote.emitDone(AudioSource.output, 'Le devis part demain.');

      await soon(() => expect(tail(), contains('Le devis part demain.')));
    },
  );

  test('les mots dictés pendant la réunion n\'apparaissent jamais dans le '
      'panneau ; la dictée est signalée', () async {
    await startFromPanel();
    final List<String> dictated = <String>[];
    final int pressAt = DateTime.now().millisecondsSinceEpoch;
    final MeetingDictation d = live.service.beginDictation()!;
    d.onText = (String text, bool _) => dictated.add(text);
    c.read(dictationActiveProvider.notifier).set(true);

    live.fakeRemote.emitDone(
      AudioSource.input,
      'DICTÉE-PANNEAU rappeler le fournisseur',
      window: UtteranceWindow(startMs: pressAt + 50, endMs: pressAt + 90),
    );
    await soon(() => expect(dictated, isNotEmpty));
    live.fakeRemote.emitDone(AudioSource.output, 'On passe au point suivant.');

    await soon(() {
      expect(tail(), contains('On passe au point suivant.'));
      expect(last()['dictating'], isTrue);
    });
    for (final Map<Object?, Object?> s in panel.updates) {
      expect(
        (s['transcript']! as List<Object?>).toString(),
        isNot(contains('DICTÉE-PANNEAU')),
      );
    }
    d.release();
  });

  test('« stop » du panneau : la note s\'arrête, le panneau revient au '
      'repos', () async {
    await startFromPanel();

    await panel.send('stop');

    await soon(() {
      expect(c.read(liveTranscriptionViewModelProvider).isRecording, isFalse);
      expect(last()['status'], 'idle');
    });
    expect(live.audio.stopCalls, 1);
  });
}
