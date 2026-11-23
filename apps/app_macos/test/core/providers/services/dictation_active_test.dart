import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/settings_fakes.dart';

// T5, besoin 5 (« never while Oats is dictating ») : l'entrée « Oats
// dicte » des suggestions, `dictationActiveProvider`, suit
// `DictationController.stateStream`.
// - vraie exactement pour DictationStarting, Listening, Transcribing ;
//   fausse pour Idle, Done, NothingHeard, ModelMissing, Error ;
// - mise à jour à chaque émission (une valeur par changement).
//
// API : `followDictation(Stream<DictationState>, void Function(bool))`
// (lib/core/providers/services/dictation.provider.dart), utilisé par
// `dictationControllerProvider` pour alimenter `dictationActiveProvider`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPrefs);
  tearDown(resetPrefs);

  group('followDictation', () {
    late StreamController<DictationState> states;
    late List<bool> seen;
    late StreamSubscription<bool> sub;

    setUp(() {
      states = StreamController<DictationState>();
      seen = <bool>[];
      sub = followDictation(states.stream, seen.add);
    });
    tearDown(() async {
      await sub.cancel();
      await states.close();
    });

    Future<void> emit(List<DictationState> list) async {
      list.forEach(states.add);
      await Future<void>.delayed(Duration.zero);
    }

    final Map<DictationState, bool> each = <DictationState, bool>{
      const DictationIdle(): false,
      const DictationStarting(): true,
      const DictationListening(): true,
      const DictationTranscribing(): true,
      const DictationDone('Bonjour', DictationDelivery.pasted): false,
      const DictationNothingHeard(): false,
      const DictationModelMissing(): false,
      const DictationError(DictationErrorReason.microphone): false,
    };
    each.forEach((DictationState s, bool expected) {
      test('${s.runtimeType} → $expected', () async {
        await emit(<DictationState>[s]);

        expect(seen, <bool>[expected]);
      });
    });

    test('suit une dictée complète : vrai à l\'appui, faux une fois le texte '
        'produit', () async {
      await emit(<DictationState>[
        const DictationIdle(),
        const DictationStarting(),
        const DictationListening(),
        const DictationTranscribing(),
        const DictationDone('Bonjour', DictationDelivery.clipboard),
        const DictationIdle(),
      ]);

      expect(seen, <bool>[false, true, false]);
    });

    test('une erreur pendant l\'écoute repasse à faux, la dictée suivante '
        'à vrai', () async {
      await emit(<DictationState>[
        const DictationListening(),
        const DictationError(DictationErrorReason.serverUnavailable),
        const DictationStarting(),
      ]);

      expect(seen, <bool>[true, false, true]);
    });
  });

  test('dictationControllerProvider alimente dictationActiveProvider : vrai '
      'dès l\'appui sur le raccourci, faux après Échap', () async {
    final LiveServiceHarness harness = LiveServiceHarness(FakeAsync());
    final FakeGlobalShortcutChannel shortcuts = FakeGlobalShortcutChannel();
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        globalShortcutChannelProvider.overrideWithValue(shortcuts),
        textOutputChannelProvider.overrideWithValue(FakeTextOutputChannel()),
        audioCaptureChannelProvider.overrideWithValue(harness.audio),
        liveTranscriptionServiceProvider.overrideWithValue(harness.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: harness.process),
        ),
      ],
    );
    addTearDown(c.dispose);
    final List<bool> seen = <bool>[];
    c.listen<bool>(
      dictationActiveProvider,
      (_, bool v) => seen.add(v),
      fireImmediately: true,
    );
    final DictationController controller = c.read(dictationControllerProvider);
    final List<DictationState> states = <DictationState>[];
    final StreamSubscription<DictationState> sub = controller.stateStream
        .listen(states.add);
    addTearDown(sub.cancel);
    await controller.apply(const DictationSettings());
    expect(c.read(dictationActiveProvider), isFalse);

    shortcuts.emit(ShortcutEvent.pressed);
    await eventually(() => expect(seen, contains(true)));
    shortcuts.emit(ShortcutEvent.cancel);
    await eventually(() {
      expect(isDictating(controller.state), isFalse);
      expect(c.read(dictationActiveProvider), isFalse);
    });

    // Une valeur par changement, dans l'ordre des états émis.
    final List<bool> expected = <bool>[false];
    for (final DictationState st in states) {
      if (isDictating(st) != expected.last) expected.add(isDictating(st));
    }
    expect(seen, expected, reason: 'états émis : $states');
    expect(states.where(isDictating), isNotEmpty);
  });
}
