import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Après Arrêter, pendant la finalisation (`finalisingRemaining` non nul),
/// l'enregistrement est fini : la pastille verte « Enregistre » de la barre
/// latérale n'est plus montrée. Un repère plus discret « Finalisation… »
/// (`transcription.live.finalising_short`) peut la remplacer. À la fin de
/// la finalisation, rien n'est montré.
void main() {
  const Key sidebarKey = ValueKey<String>('oats-sidebar');
  Finder inSidebar(String key) => find.descendant(
    of: find.byKey(sidebarKey),
    matching: find.text('$kOpen${frValue(key) as String? ?? key}$kClose'),
  );

  Future<AppFakes> pumpApp(WidgetTester tester) async {
    final AppFakes f = AppFakes(ollama: kOllamaReady);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: f.overrides,
        withMaterialApp: false,
      ),
    );
    await settle(tester);
    return f;
  }

  testWidgets('pendant l enregistrement, la pastille Enregistre est là', (
    WidgetTester tester,
  ) async {
    final AppFakes f = await pumpApp(tester);
    f.live.show(LiveTranscriptionState.initial().copyWith(isRecording: true));
    await settle(tester);

    expect(inSidebar('nav.recording'), findsOneWidget);
  });

  testWidgets('pendant la finalisation, plus de pastille Enregistre', (
    WidgetTester tester,
  ) async {
    final AppFakes f = await pumpApp(tester);
    f.live.show(
      LiveTranscriptionState.initial().copyWith(
        isRecording: true,
        finalisingRemaining: const Duration(seconds: 46),
      ),
    );
    await settle(tester);

    expect(inSidebar('nav.recording'), findsNothing);
  });

  testWidgets('la finalisation finie, ni pastille ni repère', (
    WidgetTester tester,
  ) async {
    final AppFakes f = await pumpApp(tester);
    f.live.show(
      LiveTranscriptionState.initial().copyWith(
        finalisingRemaining: const Duration(seconds: 5),
      ),
    );
    await settle(tester);
    f.live.show(LiveTranscriptionState.initial());
    await settle(tester);

    expect(inSidebar('nav.recording'), findsNothing);
    expect(inSidebar('transcription.live.finalising_short'), findsNothing);
  });
}
