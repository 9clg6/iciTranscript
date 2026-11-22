import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
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

/// Forme des réponses du coach anglais : le modèle local ne force plus
/// `format: json`, et les modèles en ligne ne l'ont jamais forcé ; ils
/// entourent ou commentent souvent le JSON.
///
/// Attendu, pour le modèle local ET pour un fournisseur en ligne (vrai
/// `activeLlmProvider`, transport factice) :
/// - JSON nu, dans un bloc ```json, précédé ou suivi de texte : lu ;
/// - pas de JSON, JSON coupé, objet vide ou d'une autre forme : état
///   `llm.error.malformed`, jamais un plantage, jamais un retour vide
///   affiché ou rangé comme s'il était valable.
void main() {
  late AppDatabase db;
  late RecordingHttpAdapter adapter;

  final String json = jsonEncode(kFeedbackJson);
  final Map<String, String> readable = <String, String>{
    'JSON nu': json,
    'bloc ```json': '```json\n$json\n```',
    'bloc ``` sans langue': '```\n$json\n```',
    'texte avant': 'Voici mon analyse de votre anglais :\n$json',
    'texte après': '$json\n\nN\'hésitez pas à me demander plus d\'exemples.',
    'texte autour et bloc':
        'Bien sûr ! Voici le retour :\n\n```json\n$json\n```\n\nBon courage.',
  };
  final Map<String, String> unreadable = <String, String>{
    'du texte seul': 'Très bon niveau, rien à corriger !',
    'un JSON coupé': '{"overall": "Bon niv',
    'un objet vide': '{}',
    'un objet d\'une autre forme': 'Résultat : {"note": 3, "niveau": "B2"}',
    'une réponse vide': '',
  };

  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await settle(tester, frames: 3);
    }
  }

  /// Note `s1` ; [cloud] : Claude configuré, autorisé et choisi ; sinon
  /// modèle local installé, envoi coupé. Le modèle répond [answer].
  Future<void> pumpCoach(
    WidgetTester tester, {
    required bool cloud,
    required String answer,
  }) async {
    final LlmProviderId id = cloud
        ? LlmProviderId.anthropic
        : LlmProviderId.ollama;
    await tester.runAsync(
      () => writeLlmPrefs(
        cloudAllowed: cloud,
        preferred: cloud ? LlmProviderId.anthropic : null,
      ),
    );
    db = memoryDatabase();
    addTearDown(db.close);
    adapter = RecordingHttpAdapter(reply: BodyReply(200, streamOf(id, answer)));
    final List<Override> overrides = <Override>[
      ...localModelOverrides(db, InstantOllamaService(installed: !cloud)),
      apiKeyStoreProvider.overrideWithValue(
        InMemoryApiKeyStore(<LlmProviderId, String>{
          if (cloud) LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
        }),
      ),
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
    await tester.tap(find.text('history.detail.english_coach'.tr()));
    await idle(tester);
  }

  for (final bool cloud in <bool>[false, true]) {
    final String who = cloud ? 'Claude' : 'modèle local';
    final String host = kProviderHost[
        cloud ? LlmProviderId.anthropic : LlmProviderId.ollama]!;

    group(who, () {
      readable.forEach((String name, String answer) {
        testWidgets('$name : le retour est lu, affiché et rangé', (
          WidgetTester tester,
        ) async {
          await pumpCoach(tester, cloud: cloud, answer: answer);

          expect(adapter.lastHost, host);
          expect(tester.takeException(), isNull);
          expect(find.textContaining('I agree'), findsWidgets);
          expect(
            find.textContaining('llm.error.malformed'.tr()),
            findsNothing,
          );
          final EnglishFeedbackEntity? saved = (await tester.runAsync(
            () => storedAnalysis(db),
          ))!.feedback;
          expect(saved?.corrections.single.corrected, 'I agree');
        });
      });

      unreadable.forEach((String name, String answer) {
        testWidgets('$name : état « réponse illisible », rien rangé, pas de '
            'plantage', (WidgetTester tester) async {
          await pumpCoach(tester, cloud: cloud, answer: answer);

          expect(adapter.lastHost, host);
          expect(tester.takeException(), isNull);
          expect(
            find.textContaining('llm.error.malformed'.tr()),
            findsOneWidget,
          );
          expect(
            (await tester.runAsync(() => storedAnalysis(db)))!.feedback,
            isNull,
          );
        });
      });
    });
  }
}
