import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// Coach de fin d'appel par le fournisseur actif (besoin B7) ; API
/// existante : `coachAfterCall(micTranscript, sessionId:)`.
void main() {
  late AppDatabase db;
  late RecordingHttpAdapter adapter;
  late InstantOllamaService ollama;

  Future<ProviderContainer> launch({
    required bool key,
    required bool cloud,
    required bool installed,
  }) async {
    await writeLlmPrefs(
      cloudAllowed: cloud,
      preferred: key ? LlmProviderId.anthropic : null,
    );
    db = memoryDatabase();
    adapter = RecordingHttpAdapter();
    ollama = InstantOllamaService(installed: installed);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, ollama),
        apiKeyStoreProvider.overrideWithValue(
          InMemoryApiKeyStore(<LlmProviderId, String>{
            if (key) LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
          }),
        ),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, kShortMeeting);
    return c;
  }

  Future<void> coach(ProviderContainer c) => c
      .read(liveTranscriptionViewModelProvider.notifier)
      .coachAfterCall('I am agree with you.', sessionId: 's1');

  test('Claude configuré et autorisé, modèle local absent : le coach passe '
      'par Claude, le retour est montré et rangé', () async {
    final ProviderContainer c = await launch(
      key: true,
      cloud: true,
      installed: false,
    );
    adapter.reply = BodyReply(
      200,
      streamOf(LlmProviderId.anthropic, jsonEncode(kFeedbackJson)),
    );

    await coach(c);

    expect(adapter.lastHost, kProviderHost[LlmProviderId.anthropic]);
    expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
    expect(
      c.read(liveTranscriptionViewModelProvider).feedback?.corrections.single
          .corrected,
      'I agree',
    );
    expect(
      (await storedAnalysis(db)).feedback?.corrections.single.corrected,
      'I agree',
    );
  });

  test('envoi coupé, modèle local installé : le coach passe par le modèle '
      'local', () async {
    final ProviderContainer c = await launch(
      key: true,
      cloud: false,
      installed: true,
    );
    adapter.reply = BodyReply(
      200,
      streamOf(LlmProviderId.ollama, jsonEncode(kFeedbackJson)),
    );

    await coach(c);

    expect(
      adapter.requests.map((RequestOptions r) => r.uri.host).toSet(),
      <String>{kProviderHost[LlmProviderId.ollama]!},
    );
    expect((await storedAnalysis(db)).feedback, isNotNull);
  });

  test('rien de disponible : rien n\'est envoyé ni téléchargé, la note '
      'reste', () async {
    final ProviderContainer c = await launch(
      key: true,
      cloud: false,
      installed: false,
    );

    await coach(c);

    expect(adapter.requests, isEmpty);
    expect(ollama.ensureReadyCalls, 0);
    expect(c.read(liveTranscriptionViewModelProvider).feedback, isNull);
  });
}
