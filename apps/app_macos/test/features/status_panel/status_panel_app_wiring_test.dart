import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/calendar_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/status_panel_fakes.dart';

// Panneau de barre de menus (T3) : l'app lancée alimente le panneau sans
// que rien d'autre ne le demande (la synchro est montée par l'app, pas par
// un écran).
void main() {
  testWidgets('au lancement de l\'app, le panneau reçoit un premier état', (
    WidgetTester tester,
  ) async {
    final FakeStatusPanelPlatform panel = FakeStatusPanelPlatform()..install();
    FakeMeetingPlatform().install();
    final AppFakes fakes = AppFakes(ollama: kOllamaReady);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: <Override>[
          ...fakes.overrides,
          liveAnswersServiceProvider.overrideWithValue(
            LiveAnswersHarness().service,
          ),
        ],
        withMaterialApp: false,
      ),
    );
    await settle(tester);

    expect(panel.updates, isNotEmpty);
    expect(panel.last['status'], 'idle');
  });
}
