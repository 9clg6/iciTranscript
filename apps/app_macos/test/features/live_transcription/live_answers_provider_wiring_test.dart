import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/detected_question.dao.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Le VRAI `liveAnswersServiceProvider` (T4) : construit sur la vraie base
/// (DetectedQuestionDao, DocumentDao), le vrai modèle résolu
/// (`liveAnswerModelProvider`) ; démarré quand un enregistrement démarre,
/// arrêté quand il s'arrête. Faux : service de transcription, serveur, micro,
/// transport HTTP (aucun réseau), Ollama « installé ». Envoi en ligne
/// autorisé avec une clé Claude : les réponses automatiques ne partent
/// qu'avec un fournisseur en ligne (le local répond à la demande).
void main() {
  late LiveServiceHarness live;
  late AppDatabase db;
  late RecordingHttpAdapter http;
  late ProviderContainer c;

  setUp(() {
    resetPrefs();
    prefsFile
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          LlmSettings.providerKey: LlmProviderId.anthropic.name,
          LlmSettings.cloudAllowedKey: true,
        }),
      );
    live = LiveServiceHarness(FakeAsync());
    db = memoryDatabase();
    // Flux ouvert : la réponse reste en cours jusqu'à l'arrêt.
    http = RecordingHttpAdapter(
      reply: const BodyReply(200, '', keepOpen: true),
    );
    c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        liveTranscriptionServiceProvider.overrideWithValue(live.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: live.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(
          InMemoryApiKeyStore(<LlmProviderId, String>{
            LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
          }),
        ),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
  });

  LiveTranscriptionViewModel vm() =>
      c.read(liveTranscriptionViewModelProvider.notifier);
  LiveAnswersService answers() => c.read(liveAnswersServiceProvider);

  Future<void> later() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  Future<String> startRecording() async {
    vm();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await vm().startSession();
    return live.transcription.currentSessionStream.value!.id;
  }

  test(
    'enregistrement démarré : une question des autres est détectée, '
    'sauvée en base pour cette session, et part vers le fournisseur choisi',
    () async {
      final String sessionId = await startRecording();

      live.fakeRemote.emitDone(
        AudioSource.output,
        'Quand est-ce que vous livrez le lot 1 ?',
      );
      await later();

      expect(answers().questions, hasLength(1));
      expect(answers().questions.single.status, LiveQuestionStatus.answering);
      expect(
        http.requests.map((RequestOptions r) => r.uri.host).toSet(),
        <String>{kProviderHost[LlmProviderId.anthropic]!},
      );
      final List<DetectedQuestion> rows = await DetectedQuestionDao(
        db,
      ).forSession(sessionId);
      expect(rows.single.question, 'Quand est-ce que vous livrez le lot 1 ?');
      expect(rows.single.source, 'output');
    },
  );

  test('enregistrement arrêté : la réponse en cours est abandonnée (requête '
      'HTTP fermée)', () async {
    await startRecording();
    live.fakeRemote.emitDone(
      AudioSource.output,
      'Quand est-ce que vous livrez le lot 1 ?',
    );
    await later();
    expect(http.requests, hasLength(1));

    await vm().stopSession();
    await later();

    expect(http.aborts, greaterThanOrEqualTo(1));
    expect(
      answers().questions.where(
        (LiveQuestion q) => q.status == LiveQuestionStatus.answering,
      ),
      isEmpty,
    );
  });

  test('avant tout enregistrement : le service existe et ne liste rien', () {
    expect(answers().questions, isEmpty);
    expect(http.requests, isEmpty);
  });
}
