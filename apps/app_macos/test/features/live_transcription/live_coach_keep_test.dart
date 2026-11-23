import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/llm_fakes.dart' show kFeedbackJson, streamOf;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Ce que le coach en direct a trouvé survit (revue de la PR #26).
///
/// Besoin : les corrections trouvées pendant la réunion sont rangées avec
/// la note DÈS Arrêter, coach d'après l'appel activé ou non : même si
/// chaque lot d'après l'appel échoue ensuite, et même si l'app quitte
/// pendant cette passe, la note les montre au lancement suivant.
///
/// Vrai view model du direct, vrai `LiveTranscriptionService` (le test joue
/// le serveur), vrai coach en direct et vrai `activeLlmProvider` (Claude
/// autorisé), transport factice, base en mémoire relue par un 2e conteneur
/// (= relance de l'app, vrai `SummaryService`).
void main() {
  late LiveServiceHarness live;
  late AppDatabase db;
  late RecordingHttpAdapter http;
  late ProviderContainer c;
  late bool quit;

  List<Override> overrides(LiveServiceHarness harness) => <Override>[
    ...localModelOverrides(db, InstantOllamaService(installed: true)),
    liveTranscriptionServiceProvider.overrideWithValue(harness.service),
    processManagerServiceProvider.overrideWithValue(
      ProcessManagerService(channel: harness.process),
    ),
    audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
    apiKeyStoreProvider.overrideWithValue(
      InMemoryApiKeyStore(<LlmProviderId, String>{
        LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
      }),
    ),
    llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
  ];

  setUp(() async {
    resetPrefs();
    await PrefsStore().update(<String, Object?>{
      LlmSettings.providerKey: LlmProviderId.anthropic.name,
      LlmSettings.cloudAllowedKey: true,
    });
    live = LiveServiceHarness(FakeAsync());
    db = memoryDatabase();
    // Le direct trouve « I am agree » → « I agree ».
    http = RecordingHttpAdapter(
      reply: BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, jsonEncode(kFeedbackJson)),
      ),
    );
    c = ProviderContainer(overrides: overrides(live));
    quit = false;
    addTearDown(() async {
      if (!quit) c.dispose();
      await db.close();
    });
  });

  LiveTranscriptionViewModel vm() =>
      c.read(liveTranscriptionViewModelProvider.notifier);
  LiveCoachService coach() => c.read(liveCoachServiceProvider);

  Future<void> userSays(String text) async {
    live.fakeRemote.emitDone(AudioSource.input, text);
    await eventually(
      () => expect(
        c
            .read(liveTranscriptionViewModelProvider)
            .segments
            .map((TranscriptSegmentEntity s) => s.text),
        contains(text),
      ),
    );
  }

  /// Note enregistrée avec le coach en direct ET le coach d'après l'appel ;
  /// le direct a trouvé une correction, une 2e phrase reste pour la passe
  /// d'après l'appel, qui répondra [afterCall].
  Future<String> meetingThenStop(FakeReply afterCall) async {
    vm();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    vm()
      ..toggleCoach()
      ..toggleLiveCoach();
    await vm().startSession();
    final String sessionId = live.transcription.currentSessionStream.value!.id;
    await userSays('I am agree with you on this point.');
    await eventually(() => expect(coach().snapshot.corrections, isNotEmpty));
    await userSays('He have sent the deck to the client.');
    http.reply = afterCall;

    await vm().stopSession();
    return sessionId;
  }

  Future<EnglishFeedbackEntity?> storedIn(
    ProviderContainer container,
    String sessionId,
  ) async => SessionAnalysis.fromStored(
    await container
        .read(summaryServiceProvider)
        .getSummaryForSession(sessionId),
  ).feedback;

  List<String>? correctedOf(EnglishFeedbackEntity? f) =>
      f?.corrections.map((EnglishCorrectionEntity x) => x.corrected).toList();

  test('rangé dès Arrêter, avant la passe d\'après l\'appel', () async {
    final String id = await meetingThenStop(const HangReply());

    expect(correctedOf(await storedIn(c, id)), contains('I agree'));
  });

  test('chaque lot d\'après l\'appel échoue : la correction du direct reste, '
      'les phrases restantes sont non analysées', () async {
    final String id = await meetingThenStop(const UnreachableReply());

    await eventually(() async {
      final EnglishFeedbackEntity? f = await storedIn(c, id);
      expect(f?.unanalyzedSegmentIds, isNotEmpty);
      expect(correctedOf(f), contains('I agree'));
    });
  });

  test('l\'app quitte pendant la passe d\'après l\'appel : au lancement '
      'suivant, la note montre la correction du direct', () async {
    final String id = await meetingThenStop(const HangReply());
    await eventually(
      () => expect(http.requests.length, greaterThanOrEqualTo(2)),
    );

    // Quitter, puis relancer sur la même base.
    c.dispose();
    quit = true;
    final ProviderContainer relaunched = ProviderContainer(
      overrides: overrides(LiveServiceHarness(FakeAsync())),
    );
    addTearDown(relaunched.dispose);

    expect(correctedOf(await storedIn(relaunched, id)), contains('I agree'));
  });
}
