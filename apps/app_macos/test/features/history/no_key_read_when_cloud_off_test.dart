import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/platform/file_picker.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/documents/presentation/documents.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/document_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Envoi en ligne coupé : la note et la page Documents ne lisent aucune clé
/// de fournisseur en ligne dans le trousseau (sur un build ad hoc, chaque
/// lecture peut afficher une invite du trousseau). Seule la section IA des
/// Réglages peut en lire, pour montrer la clé masquée : non couvert ici.
void main() {
  late AppDatabase db;
  late CountingApiKeyStore store;
  late RecordingHttpAdapter adapter;

  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await settle(tester, frames: 3);
    }
  }

  Future<List<Override>> world(
    WidgetTester tester, {
    bool cloud = false,
  }) async {
    await tester.runAsync(
      () => writeLlmPrefs(
        cloudAllowed: cloud,
        preferred: LlmProviderId.anthropic,
      ),
    );
    db = memoryDatabase();
    addTearDown(db.close);
    store = CountingApiKeyStore(<LlmProviderId, String>{
      LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
      LlmProviderId.openai: 'sk-openai-test-SECRET-9876543210',
    });
    adapter = RecordingHttpAdapter(
      reply: BodyReply(
        200,
        streamOf(LlmProviderId.ollama, 'Le budget est attendu vendredi.'),
      ),
    );
    return <Override>[
      ...localModelOverrides(db, InstantOllamaService(installed: true)),
      apiKeyStoreProvider.overrideWithValue(store),
      llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      ollamaSetupViewModelProvider.overrideWith(
        () => FakeOllamaSetupViewModel(kOllamaReady),
      ),
    ];
  }

  Future<void> pumpNote(WidgetTester tester, {bool cloud = false}) async {
    final List<Override> overrides = await world(tester, cloud: cloud);
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides);
      await seedNote(c, kShortMeeting);
      c.dispose();
    });
    store.reads.clear();
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: overrides,
    );
    await idle(tester);
  }

  testWidgets('ouvrir une note : aucune lecture de clé', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester);

    expect(find.text('Point budget'), findsOneWidget);
    expect(store.cloudReads, isEmpty);
  });

  for (final String action in <String>[
    'history.detail.summarize',
    'history.detail.english_coach',
  ]) {
    testWidgets('$action avec le modèle local : aucune lecture de clé', (
      WidgetTester tester,
    ) async {
      await pumpNote(tester);

      await tester.tap(find.text(action.tr()));
      await idle(tester);

      expect(adapter.lastHost, kProviderHost[LlmProviderId.ollama]);
      expect(store.cloudReads, isEmpty);
    });
  }

  testWidgets('témoin : envoi autorisé, Résumer lit bien la clé (le '
      'compteur compte)', (WidgetTester tester) async {
    await pumpNote(tester, cloud: true);
    adapter.reply = BodyReply(
      200,
      streamOf(LlmProviderId.anthropic, 'Le budget est attendu vendredi.'),
    );

    await tester.tap(find.text('history.detail.summarize'.tr()));
    await idle(tester);

    expect(adapter.lastHost, kProviderHost[LlmProviderId.anthropic]);
    expect(store.cloudReads, contains(LlmProviderId.anthropic));
  });

  testWidgets('ouvrir la page Documents : aucune lecture de clé', (
    WidgetTester tester,
  ) async {
    final List<Override> overrides = await world(tester);
    store.reads.clear();
    await pumpLocalized(
      tester,
      const DocumentsScreen(),
      settle: false,
      overrides: <Override>[
        ...overrides,
        filePickerProvider.overrideWithValue(FakeFilePicker()),
      ],
    );
    await idle(tester);

    expect(find.text('documents.add'.tr()), findsOneWidget);
    expect(store.cloudReads, isEmpty);
  });
}
