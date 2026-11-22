import 'dart:async';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Modèle local : au lancement on DÉTECTE seulement ; le téléchargement
/// (~106 Mo + ~4 Go) ne part que d'un clic dans Réglages.
///
/// API supposée : `OllamaService.isInstalled()` (détection sans
/// téléchargement ni démarrage), `OllamaService.ensureReady(onProgress:)`
/// (installation), `OllamaSetupViewModel` : build() détecte, `install()`
/// lance l'installation, `retry()` la relance après une erreur.
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

  final Finder sidebar = find.byKey(const ValueKey<String>('oats-sidebar'));
  Finder navItem(String key) =>
      find.descendant(of: sidebar, matching: find.text(key.tr()));
  final Finder install = find.text('settings.local_model.install'.tr());

  Future<FakeOllamaService> pumpApp(
    WidgetTester tester, {
    required bool installed,
  }) async {
    final FakeOllamaService service = FakeOllamaService(installed: installed);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: AppFakes(sessions: sessions, ollamaService: service)
            .overrides,
        withMaterialApp: false,
      ),
    );
    await settle(tester);
    return service;
  }

  bool isReady(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(RootAppWidget)),
  ).read(ollamaSetupViewModelProvider).isReady;

  Future<void> goTo(WidgetTester tester, String nav) async {
    await tester.tap(navItem(nav));
    await settle(tester);
  }

  Future<void> openNote(WidgetTester tester) async {
    await goTo(tester, 'nav.home');
    await tester.tap(find.text('Point équipe'));
    await settle(tester);
  }

  final Finder configure = find.textContaining('llm.configure_model'.tr());

  group('au lancement', () {
    testWidgets('modèle absent : détecte, ne télécharge rien, pas prêt', (
      WidgetTester tester,
    ) async {
      final FakeOllamaService service = await pumpApp(tester, installed: false);

      expect(service.installCalls, 0);
      expect(service.detectCalls, greaterThanOrEqualTo(1));
      expect(isReady(tester), isFalse);
      await openNote(tester);
      expect(configure, findsWidgets);
    });

    testWidgets('modèle déjà installé : détecte, ne télécharge rien, prêt', (
      WidgetTester tester,
    ) async {
      final FakeOllamaService service = await pumpApp(tester, installed: true);

      expect(service.installCalls, 0);
      expect(isReady(tester), isTrue);
      await openNote(tester);
      expect(find.text('Point équipe'), findsWidgets);
      expect(configure, findsNothing);
    });
  });

  group('Réglages', () {
    testWidgets('installer : progression par étape, puis prêt sans '
        'redémarrage et l\'invite disparaît de la note', (
      WidgetTester tester,
    ) async {
      final FakeOllamaService service = await pumpApp(tester, installed: false);
      await goTo(tester, 'nav.settings');

      expect(install.hitTestable(), findsOneWidget);
      expect(service.installCalls, 0);

      await tester.tap(install);
      await settle(tester);
      expect(service.installCalls, 1);

      service.progress!(OllamaSetupStage.downloadingModel, 0.42);
      await settle(tester);
      expect(find.textContaining('ollama.step_model'.tr()), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is ProgressIndicator &&
              w.value != null &&
              (w.value! - 0.42).abs() < 0.001,
        ),
        findsOneWidget,
      );

      service.installed = true;
      service.installRun!.complete();
      await settle(tester);

      expect(isReady(tester), isTrue);
      expect(install, findsNothing);
      await openNote(tester);
      expect(configure, findsNothing);
    });

    testWidgets('après une erreur, on peut relancer l\'installation', (
      WidgetTester tester,
    ) async {
      final FakeOllamaService service = await pumpApp(tester, installed: false);
      await goTo(tester, 'nav.settings');
      await tester.tap(install);
      await settle(tester);

      service.installRun!.completeError(Exception('réseau coupé'));
      await settle(tester);
      expect(find.textContaining('ollama.error'.tr()), findsOneWidget);
      expect(isReady(tester), isFalse);

      final Finder retry = find.text('common.action.retry'.tr()).hitTestable();
      await tester.tap(
        retry.evaluate().isNotEmpty ? retry.first : install.hitTestable().first,
      );
      await settle(tester);
      expect(service.installCalls, 2);
    });

    testWidgets('modèle déjà installé : affiché prêt, pas de bouton installer', (
      WidgetTester tester,
    ) async {
      final FakeOllamaService service = await pumpApp(tester, installed: true);
      await goTo(tester, 'nav.settings');

      expect(find.textContaining('settings.local_model.ready'.tr()), findsOneWidget);
      expect(install, findsNothing);
      expect(service.installCalls, 0);
    });
  });
}

/// Service Ollama factice : rien ne touche le réseau, le disque ni un process.
///
/// [isInstalled] / [isFullyReady] = détection (renvoie [installed]) ;
/// [ensureReady] = installation, pilotée par le test via [progress] et
/// [installRun].
class FakeOllamaService extends OllamaService {
  FakeOllamaService({required this.installed});

  bool installed;
  int detectCalls = 0;
  int installCalls = 0;
  void Function(OllamaSetupStage stage, double progress)? progress;
  Completer<void>? installRun;

  @override
  Future<bool> isInstalled() async {
    detectCalls++;
    return installed;
  }

  @override
  Future<bool> isFullyReady() async {
    detectCalls++;
    return installed;
  }

  @override
  Future<void> ensureReady({
    void Function(OllamaSetupStage stage, double progress)? onProgress,
  }) {
    installCalls++;
    progress = onProgress;
    installRun = Completer<void>();
    return installRun!.future;
  }

  @override
  Future<void> unloadModel() async {}

  @override
  Future<void> dispose() async {}
}
