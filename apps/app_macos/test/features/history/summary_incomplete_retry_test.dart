import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Après un résumé incomplet (montré et signalé, pas rangé) : la note offre
/// toujours « Résumer » pour relancer, et un résumé complet déjà rangé n'est
/// pas remplacé par l'incomplet.
void main() {
  late AppDatabase db;
  late ScriptedLlmProvider llm;

  const String previous = 'Résumé complet précédent : budget validé.';
  const String cut = 'Les participants ont décidé que le budget sera de';
  const String retried = 'Le budget est fixé à 40 000 euros.';

  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await settle(tester, frames: 3);
    }
  }

  List<Override> overrides() => <Override>[
    ...localModelOverrides(db, InstantOllamaService(installed: true)),
    apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
    llmDioProvider.overrideWithValue(
      Dio()..httpClientAdapter = RecordingHttpAdapter(),
    ),
    activeLlmProviderProvider.overrideWith((Ref ref) async => llm),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
  ];

  Future<void> openScreen(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: overrides(),
    );
    await idle(tester);
  }

  /// Note `s1` ; [stored] : résumé complet déjà rangé. Réponses : [answers]
  /// dans l'ordre des requêtes.
  Future<void> pumpNote(
    WidgetTester tester, {
    String? stored,
    required List<String> answers,
  }) async {
    resetPrefs();
    db = memoryDatabase();
    addTearDown(db.close);
    llm = ScriptedLlmProvider(
      (LlmChatRequest r, int i) => Stream<String>.value(answers[i]),
    );
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides());
      await seedNote(c, kShortMeeting);
      if (stored != null) {
        await c
            .read(summaryServiceProvider)
            .saveSummary(
              sessionId: 's1',
              content: SessionAnalysis(summary: stored).toStored(),
            );
      }
      c.dispose();
    });
    await openScreen(tester);
  }

  Future<void> summarize(WidgetTester tester) async {
    await tester.tap(find.text('history.detail.summarize'.tr()));
    await idle(tester);
  }

  testWidgets('après un résumé incomplet, « Résumer » reste offert et relance '
      'une demande ; le résumé complet obtenu est rangé', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, answers: <String>[cut, retried]);

    await summarize(tester);
    expect(find.textContaining('llm.incomplete'.tr()), findsOneWidget);
    expect(find.text('history.detail.summarize'.tr()), findsOneWidget);

    await summarize(tester);

    expect(llm.requests, hasLength(2));
    expect(find.textContaining(retried), findsOneWidget);
    expect(find.textContaining('llm.incomplete'.tr()), findsNothing);
    expect(
      (await tester.runAsync(() => storedAnalysis(db)))!.summary,
      retried,
    );
  });

  testWidgets('un résumé complet déjà rangé n\'est pas remplacé par un '
      'incomplet, ni en base ni à la réouverture', (WidgetTester tester) async {
    await pumpNote(tester, stored: previous, answers: <String>[cut]);
    expect(find.textContaining(previous), findsOneWidget);

    await summarize(tester);

    expect(find.textContaining('llm.incomplete'.tr()), findsOneWidget);
    expect(
      (await tester.runAsync(() => storedAnalysis(db)))!.summary,
      previous,
    );

    await tester.pumpWidget(const SizedBox());
    await openScreen(tester);

    expect(find.textContaining(previous), findsOneWidget);
    expect(find.textContaining(cut), findsNothing);
  });
}
