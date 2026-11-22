import 'dart:io';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Réglages (T2) : un raccourci de dictée qui ne s'enregistre pas (déjà pris
/// par une autre app) se voit dans Réglages, au lieu d'échouer en silence.
///
/// API supposée : `dictationShortcutStatusProvider`, un
/// `@riverpod Stream<ShortcutStatus>` dans
/// lib/core/providers/services/dictation.provider.dart.
void main() {
  final File prefs = File('${appDataDirectory()}/prefs.json');
  setUp(() {
    expect(prefs.path, startsWith(Directory.systemTemp.path));
    if (prefs.existsSync()) prefs.deleteSync();
  });

  final Finder sidebar = find.byKey(const ValueKey<String>('oats-sidebar'));
  // Évalué à l'usage : .tr() doit tourner après le chargement des traductions.
  Finder unavailable() =>
      find.text('settings.dictation.shortcut_unavailable'.tr());

  Future<void> openSettings(WidgetTester tester, ShortcutStatus status) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: <Override>[
          ...AppFakes(sessions: const <SessionEntity>[]).overrides,
          dictationShortcutStatusProvider.overrideWith(
            (Ref ref) => Stream<ShortcutStatus>.value(status),
          ),
        ],
        withMaterialApp: false,
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(of: sidebar, matching: find.text('nav.settings'.tr())),
    );
    await settle(tester);
  }

  testWidgets('raccourci déjà pris : message d erreur dans Réglages', (
    WidgetTester tester,
  ) async {
    await openSettings(tester, ShortcutStatus.unavailable);

    expect(frValue('settings.dictation.shortcut_unavailable'), isA<String>());
    expect(unavailable(), findsOneWidget);
  });

  testWidgets('raccourci enregistré : pas de message d erreur', (
    WidgetTester tester,
  ) async {
    await openSettings(tester, ShortcutStatus.registered);

    expect(unavailable(), findsNothing);
  });

  testWidgets('raccourci par défaut affiché dans Réglages : ⌃⌥Espace', (
    WidgetTester tester,
  ) async {
    await openSettings(tester, ShortcutStatus.registered);

    expect(find.textContaining('⌃⌥Espace'), findsOneWidget);
    expect(find.textContaining(RegExp(r'(?<!⌃)⌥Espace')), findsNothing);
  });
}
