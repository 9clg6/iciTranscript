import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Chemin local, démon arrêté : avant cette PR, Résumer / Coach passaient
/// par `OllamaService`, qui démarrait le démon. Au lancement propre de
/// l'app, rien ne l'a démarré : le premier résumé doit quand même marcher.
///
/// Attendu : le démon est démarré AVANT la requête ; une attente bornée
/// (au plus [startBound]) ; un démon qui ne démarre pas, ou ne répond pas
/// dans la borne, donne l'état `llm.error.unreachable`, rien n'est envoyé ni
/// rangé.
///
/// Démarrage = `OllamaService.ensureReady()` (modèle déjà présent : rien à
/// télécharger), remplacé par [StoppedDaemonOllamaService].
const Duration startBound = Duration(seconds: 60);

void main() {
  late AppDatabase db;
  late RecordingHttpAdapter adapter;
  late StoppedDaemonOllamaService ollama;

  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await settle(tester, frames: 3);
    }
  }

  Future<void> pumpNote(
    WidgetTester tester, {
    Object? startError,
    bool hangOnStart = false,
  }) async {
    await tester.runAsync(() => writeLlmPrefs(cloudAllowed: false));
    db = memoryDatabase();
    addTearDown(db.close);
    adapter = RecordingHttpAdapter(
      reply: BodyReply(
        200,
        streamOf(LlmProviderId.ollama, 'Le budget est attendu vendredi.'),
      ),
    );
    ollama = StoppedDaemonOllamaService(
      sentSoFar: () => adapter.requests.length,
      startError: startError,
      hangOnStart: hangOnStart,
    );
    final List<Override> overrides = <Override>[
      ...localModelOverrides(db, ollama),
      apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
      llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      ollamaSetupViewModelProvider.overrideWith(
        () => FakeOllamaSetupViewModel(kOllamaReady),
      ),
    ];
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides);
      await seedNote(c, kShortMeeting);
      c.dispose();
    });
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: overrides,
    );
    await idle(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    await tester.tap(find.text(key.tr()));
    await idle(tester);
  }

  testWidgets('démon arrêté : il est démarré avant la requête, le premier '
      'résumé marche', (WidgetTester tester) async {
    await pumpNote(tester);

    await tapAction(tester, 'history.detail.summarize');

    expect(ollama.ensureReadyCalls, greaterThan(0));
    expect(ollama.sentAtStart.first, 0, reason: 'démarré avant la requête');
    expect(adapter.lastHost, kProviderHost[LlmProviderId.ollama]);
    expect(find.textContaining('Le budget est attendu vendredi.'), findsOneWidget);
  });

  testWidgets('démon arrêté : le coach le démarre aussi avant sa requête', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester);

    await tapAction(tester, 'history.detail.english_coach');

    expect(ollama.sentAtStart, isNotEmpty);
    expect(ollama.sentAtStart.first, 0);
  });

  for (final String action in <String>[
    'history.detail.summarize',
    'history.detail.english_coach',
  ]) {
    testWidgets('$action, démon qui ne démarre pas : « injoignable », rien '
        'envoyé ni rangé', (WidgetTester tester) async {
      await pumpNote(
        tester,
        startError: Exception('Ollama ne répond pas après 30s.'),
      );

      await tapAction(tester, action);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('llm.error.unreachable'.tr()), findsOneWidget);
      expect(adapter.requests, isEmpty);
      expect(
        await tester.runAsync(() => storedRow(db)),
        isNull,
      );
    });
  }

  testWidgets('démon qui ne répond jamais : « injoignable » dans la borne, '
      'rien envoyé', (WidgetTester tester) async {
    await pumpNote(tester, hangOnStart: true);

    await tapAction(tester, 'history.detail.summarize');
    await tester.pump(startBound + const Duration(seconds: 1));
    await idle(tester);

    expect(find.textContaining('llm.error.unreachable'.tr()), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });
}
