import 'package:core_data/database/app_database.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/file_picker.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/document_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';

/// Application entière : l'entrée Documents de la barre latérale ouvre la
/// vraie page Documents (plus le texte « arrive bientôt »).
void main() {
  testWidgets('Documents dans la barre latérale : page vide avec « Ajouter un '
      'document »', (WidgetTester tester) async {
    final AppDatabase db = memoryDatabase();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: <Override>[
          ...AppFakes(ollama: kOllamaReady).overrides,
          databaseProvider.overrideWithValue(db),
          filePickerProvider.overrideWithValue(FakeFilePicker()),
        ],
        withMaterialApp: false,
      ),
    );
    await settle(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('oats-sidebar')),
        matching: find.text('nav.documents'.tr()),
      ),
    );
    for (int i = 0;
        i < 30 && find.text('documents.add'.tr()).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(tester, frames: 2);
    }

    expect(find.text('documents.add'.tr()), findsOneWidget);
    expect(find.text('documents.empty_title'.tr()), findsOneWidget);
  });
}
