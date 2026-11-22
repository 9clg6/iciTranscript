import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/platform/dev_data_directory.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Un lancement de dev (debug, profile, OATS_DATA_DIR) n'ouvre pas les vraies
/// notes : la barre latérale le dit, pour que personne ne prenne ces notes
/// pour les siennes.
void main() {
  final Finder sidebar = find.byKey(const ValueKey<String>('oats-sidebar'));
  Finder devLabel() =>
      find.descendant(of: sidebar, matching: find.text('app.dev_data'.tr()));

  Future<void> pumpApp(WidgetTester tester, {required bool devData}) async {
    final AppFakes fakes = AppFakes(ollama: kOllamaReady);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: <Override>[
          ...fakes.overrides,
          isDevDataDirectoryProvider.overrideWithValue(devData),
        ],
        withMaterialApp: false,
      ),
    );
    await settle(tester);
  }

  testWidgets('sur un dossier de dev, la barre latérale affiche '
      '« données de dev »', (WidgetTester tester) async {
    await pumpApp(tester, devData: true);

    expect(devLabel(), findsOneWidget);
    expect(isOnScreen(devLabel()), isTrue);
  });

  testWidgets('sur le vrai dossier (release), aucune mention de dev', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, devData: false);

    expect(devLabel(), findsNothing);
  });
}
