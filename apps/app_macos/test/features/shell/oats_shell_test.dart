import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Application entière (RootAppWidget + AppRouter réel) : le lancement n'est
/// plus bloqué par Ollama, la barre latérale navigue dans le shell.
void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 9);
  final List<SessionEntity> sessions = <SessionEntity>[
    FakeData.createSession(
      id: 'point',
      title: 'Point équipe',
      createdAt: today,
      updatedAt: today,
      durationSeconds: 52 * 60,
    ),
  ];

  const Key sidebarKey = ValueKey<String>('oats-sidebar');
  final Finder sidebar = find.byKey(sidebarKey);
  Finder navItem(String key) =>
      find.descendant(of: sidebar, matching: find.text(key.tr()));

  Future<AppFakes> pumpApp(WidgetTester tester, {AppFakes? fakes}) async {
    final AppFakes f =
        fakes ?? AppFakes(sessions: sessions, ollama: kOllamaReady);
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

  void expectSelected(WidgetTester tester, String key, bool selected) {
    expect(
      tester.getSemantics(navItem(key)),
      isSemantics(isSelected: selected),
      reason: '$key sélectionné = $selected',
    );
  }

  Future<void> tapNav(WidgetTester tester, String key) async {
    await tester.tap(navItem(key));
    await settle(tester);
  }

  group('lancement sans modèle local', () {
    const Map<String, OllamaSetupState> notReady = <String, OllamaSetupState>{
      'absent': kOllamaAbsent,
      'en téléchargement': OllamaSetupState(
        stage: OllamaSetupStage.downloadingBinary,
        progress: 0.3,
      ),
      'pas encore vérifié': OllamaSetupState(),
    };

    notReady.forEach((String name, OllamaSetupState ollama) {
      testWidgets('Ollama $name : l\'accueil s\'affiche, pas d\'écran bloquant', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          fakes: AppFakes(sessions: sessions, ollama: ollama),
        );

        expect(find.byType(OllamaSetupScreen), findsNothing);
        expect(isOnScreen(navItem('nav.home')), isTrue);
        expect(isOnScreen(find.text('Point équipe')), isTrue);
      });

      testWidgets('Ollama $name : « Nouvelle note » démarre l\'enregistrement', (
        WidgetTester tester,
      ) async {
        final AppFakes f = await pumpApp(
          tester,
          fakes: AppFakes(sessions: sessions, ollama: ollama),
        );

        await tester.tap(find.text('home.new_note'.tr()).hitTestable().first);
        await settle(tester);

        expect(f.live.startCalls, 1);
      });
    });

    testWidgets('le nom du produit affiché dans la barre latérale est celui '
        'de app.name', (WidgetTester tester) async {
      await pumpApp(tester);

      expect(
        find.descendant(of: sidebar, matching: find.text('app.name'.tr())),
        findsOneWidget,
      );
    });
  });

  group('barre latérale', () {
    testWidgets('propose Accueil, Documents, Coach anglais, Réglages ; '
        'Accueil est sélectionné au lancement', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester);

      for (final String key in <String>[
        'nav.home',
        'nav.documents',
        'nav.coach',
        'nav.settings',
      ]) {
        expect(isOnScreen(navItem(key)), isTrue, reason: key);
      }
      expectSelected(tester, 'nav.home', true);
      expectSelected(tester, 'nav.documents', false);
      expectSelected(tester, 'nav.coach', false);
      expectSelected(tester, 'nav.settings', false);
      handle.dispose();
    });

    testWidgets('choisir Documents puis Coach anglais déplace la sélection', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester);

      await tapNav(tester, 'nav.documents');
      expectSelected(tester, 'nav.documents', true);
      expectSelected(tester, 'nav.home', false);

      await tapNav(tester, 'nav.coach');
      expectSelected(tester, 'nav.coach', true);
      expectSelected(tester, 'nav.documents', false);
      handle.dispose();
    });

    testWidgets('Réglages s\'ouvre comme une page du shell, pas un dialogue', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester);

      await tapNav(tester, 'nav.settings');

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      // Pas de barrière modale : la barre latérale reste cliquable.
      expect(isOnScreen(navItem('nav.home')), isTrue);
      expectSelected(tester, 'nav.settings', true);
      expectSelected(tester, 'nav.home', false);

      await tapNav(tester, 'nav.home');
      expect(find.byType(SettingsScreen), findsNothing);
      expect(isOnScreen(find.text('Point équipe')), isTrue);
      handle.dispose();
    });
  });

  group('note', () {
    Finder back() => find.bySemanticsLabel('common.action.back'.tr()).first;

    testWidgets('ouvrir une note puis Retour revient à l\'accueil', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester);

      await tester.tap(find.text('Point équipe'));
      await settle(tester);
      expect(isOnScreen(find.text('history.detail.delete'.tr())), isTrue);

      await tester.tap(back());
      await settle(tester);

      expect(find.byType(SessionDetailScreen), findsNothing);
      expect(isOnScreen(find.text('Point équipe')), isTrue);
      expectSelected(tester, 'nav.home', true);
      handle.dispose();
    });

    testWidgets('note illisible : message d\'erreur et Retour vers l\'accueil', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        fakes: AppFakes(
          sessions: sessions,
          ollama: kOllamaReady,
          detail: (String _) async => throw StateError('base illisible'),
        ),
      );

      await tester.tap(find.text('Point équipe'));
      await settle(tester);
      expect(isOnScreen(find.text('common.error.generic'.tr())), isTrue);

      await tester.tap(back());
      await settle(tester);

      expect(find.byType(SessionDetailScreen), findsNothing);
      expect(isOnScreen(find.text('Point équipe')), isTrue);
      handle.dispose();
    });
  });
}
