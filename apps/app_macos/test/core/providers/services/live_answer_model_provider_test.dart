import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answer_model.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';

import '../../../helpers/local_model_fakes.dart';
import '../../../helpers/settings_fakes.dart';

/// Modèle qui répond aux questions en direct (T4, besoin 8) : l'interrupteur
/// d'envoi est respecté ; sans modèle prêt, null (l'écran affiche
/// « configurer un modèle »), jamais un silence ni un envoi en ligne.
///
/// API supposée (lib/core/providers/services/live_answer_model.provider.dart) :
/// `@riverpod Future<LiveAnswerModel?> liveAnswerModel(Ref ref)` : le
/// fournisseur de `activeLlmProviderProvider` et l'id du modèle utilisé
/// (`LlmSettings.modelFor`) ; null si ce fournisseur est le modèle local et
/// que `OllamaService.isFullyReady()` est faux. Pas gardé en vie : relu à
/// chaque question.
const String _claudeKey = 'sk-ant-test-SECRET-0123456789';

void main() {
  late InMemoryApiKeyStore keys;
  late RecordingHttpAdapter adapter;

  setUp(() {
    resetPrefs();
    keys = InMemoryApiKeyStore(<LlmProviderId, String>{
      LlmProviderId.anthropic: _claudeKey,
    });
    adapter = RecordingHttpAdapter();
  });

  void writePrefs({required bool cloudAllowed}) {
    prefsFile
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          LlmSettings.providerKey: LlmProviderId.anthropic.name,
          LlmSettings.cloudAllowedKey: cloudAllowed,
        }),
      );
  }

  ProviderContainer launch({required bool localInstalled}) {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        apiKeyStoreProvider.overrideWithValue(keys),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        ollamaServiceProvider.overrideWithValue(
          InstantOllamaService(installed: localInstalled),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('envoi coupé, Claude choisi avec sa clé, modèle local absent : aucun '
      'modèle (configurer), rien envoyé', () async {
    writePrefs(cloudAllowed: false);
    final ProviderContainer c = launch(localInstalled: false);

    final LiveAnswerModel? model = await c.read(liveAnswerModelProvider.future);

    expect(model, isNull);
    expect(adapter.requests, isEmpty);
  });

  test('envoi coupé, modèle local installé : le local répond, rien ne part '
      'vers un service en ligne', () async {
    writePrefs(cloudAllowed: false);
    final ProviderContainer c = launch(localInstalled: true);

    final LiveAnswerModel? model = await c.read(liveAnswerModelProvider.future);
    expect(model, isNotNull);
    expect(model!.modelId, LlmSettings.defaultModel(LlmProviderId.ollama));
    await sendPing(model.provider);

    expect(
      adapter.requests.map((RequestOptions r) => r.uri.host).toSet(),
      <String>{kProviderHost[LlmProviderId.ollama]!},
    );
  });

  test('envoi autorisé : Claude, avec l\'id de son modèle', () async {
    writePrefs(cloudAllowed: true);
    final ProviderContainer c = launch(localInstalled: false);

    final LiveAnswerModel? model = await c.read(liveAnswerModelProvider.future);
    expect(model!.modelId, LlmSettings.defaultModel(LlmProviderId.anthropic));
    await sendPing(model.provider);

    expect(adapter.lastHost, kProviderHost[LlmProviderId.anthropic]);
  });
}
