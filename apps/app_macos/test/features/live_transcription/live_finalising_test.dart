import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/localized_app.dart';

/// Tour 5 bis, point 3 : après Arrêter, tant que le service publie de
/// l'audio restant à transcrire, l'écran montre « Finalisation de la
/// transcription… » avec le temps restant (« ~46 s ») et une action
/// « Passer » qui appelle `skipFinalising()` ; Arrêter n'est plus proposé.
/// À la fin, l'état de finalisation disparaît.
///
/// API supposée : `LiveTranscriptionState.finalisingRemaining`
/// (`Duration?`, null hors finalisation, alimenté par
/// `finalisingRemainingStream`) et `LiveTranscriptionViewModel
/// .skipFinalising()`. Textes lus dans fr.json (marqués ⟦…⟧ par le banc).
class _FinalisingViewModel extends LiveTranscriptionViewModel {
  int skips = 0;

  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial().copyWith(
    isRecording: true,
    finalisingRemaining: const Duration(seconds: 46),
  );

  @override
  void skipFinalising() => skips++;

  void finish() =>
      state = state.copyWith(isRecording: false, finalisingRemaining: null);
}

void main() {
  late _FinalisingViewModel vm;
  late List<Override> overrides;

  setUp(() {
    vm = _FinalisingViewModel();
    overrides = <Override>[
      liveTranscriptionViewModelProvider.overrideWith(() => vm),
    ];
  });

  String fr(String key) => frValue(key)! as String;
  String shown(String key, [String? arg]) =>
      '$kOpen${arg == null ? fr(key) : fr(key).replaceFirst('{}', arg)}$kClose';

  testWidgets('la finalisation et le temps restant sont affichés', (
    WidgetTester tester,
  ) async {
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      overrides: overrides,
      settle: false,
    );

    expect(find.text(shown('transcription.live.finalising')), findsOneWidget);
    expect(
      find.text(shown('transcription.live.finalising_remaining', '46')),
      findsOneWidget,
    );
  });

  testWidgets('Arrêter n est plus proposé pendant la finalisation', (
    WidgetTester tester,
  ) async {
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      overrides: overrides,
      settle: false,
    );

    expect(find.text(shown('transcription.live.stop')), findsNothing);
  });

  testWidgets('Passer appelle skipFinalising', (WidgetTester tester) async {
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      overrides: overrides,
      settle: false,
    );

    await tester.tap(find.text(shown('transcription.live.skip_finalising')));
    await tester.pump();

    expect(vm.skips, 1);
  });

  testWidgets('à la fin, l état de finalisation disparaît', (
    WidgetTester tester,
  ) async {
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      overrides: overrides,
      settle: false,
    );

    vm.finish();
    await tester.pump();

    expect(find.text(shown('transcription.live.finalising')), findsNothing);
    expect(
      find.text(shown('transcription.live.skip_finalising')),
      findsNothing,
    );
  });
}
