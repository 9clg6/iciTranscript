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
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// L'invite « configurer un modèle » de la note suit le fournisseur
/// réellement disponible (besoin B7), pas seulement le modèle local : avec
/// Claude configuré et autorisé, la note n'invite pas à installer Ollama.
void main() {
  late AppDatabase db;
  late RecordingHttpAdapter adapter;

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
    required bool cloud,
  }) async {
    await tester.runAsync(
      () => writeLlmPrefs(
        cloudAllowed: cloud,
        preferred: LlmProviderId.anthropic,
      ),
    );
    db = memoryDatabase();
    addTearDown(db.close);
    adapter = RecordingHttpAdapter(
      reply: BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, 'Le budget est attendu vendredi.'),
      ),
    );
    final List<Override> overrides = <Override>[
      ...localModelOverrides(db, InstantOllamaService(installed: false)),
      apiKeyStoreProvider.overrideWithValue(
        InMemoryApiKeyStore(<LlmProviderId, String>{
          LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
        }),
      ),
      llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      ollamaSetupViewModelProvider.overrideWith(
        () => FakeOllamaSetupViewModel(const OllamaSetupState()),
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

  Finder configure() => find.textContaining('llm.configure_model'.tr());

  testWidgets('Claude configuré et autorisé, modèle local absent : pas '
      'd\'invite, Résumer affiche le résumé de Claude', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, cloud: true);

    expect(configure(), findsNothing);

    await tester.tap(find.text('history.detail.summarize'.tr()));
    await idle(tester);

    expect(adapter.lastHost, kProviderHost[LlmProviderId.anthropic]);
    expect(find.textContaining('Le budget est attendu vendredi.'), findsOneWidget);
  });

  testWidgets('clé rangée mais envoi coupé, modèle local absent : invite à '
      'configurer, Résumer n\'envoie rien', (WidgetTester tester) async {
    await pumpNote(tester, cloud: false);

    expect(configure(), findsWidgets);

    await tester.tap(find.text('history.detail.summarize'.tr()));
    await idle(tester);

    expect(adapter.requests, isEmpty);
    expect(find.textContaining('Le budget est attendu vendredi.'), findsNothing);
  });
}
