import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/summary.dao.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answer_model.provider.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/llm_fakes.dart' show kFeedbackJson, streamOf;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Coach en direct branché pour de vrai : vrai view model du direct, vrai
/// `LiveTranscriptionService` (le test joue le serveur), vrai
/// `activeLlmProvider` (prefs.json + trousseau en mémoire), transport HTTP
/// factice (aucun réseau), Ollama factice « installé », base en mémoire.
///
/// Besoin : interrupteur « Coach en direct » coupé par défaut, qui survit à
/// un redémarrage ; activé, les phrases anglaises finales de l'utilisateur
/// partent au fournisseur EN LIGNE configuré et autorisé, jamais au modèle
/// local, jamais quand l'envoi est coupé (même en pleine réunion) ; jamais
/// une phrase dictée pendant la réunion (la dictée la route hors de
/// `finalizedSegmentsStream`, épinglé par live_answers_dictation_test) ; un
/// modèle muet ne bloque ni la transcription ni Arrêter ; ce que le direct a
/// trouvé est rangé dans la note à l'arrêt, même coach d'après l'appel
/// coupé.
///
/// API supposée : `LiveTranscriptionState.isLiveCoachEnabled`,
/// `LiveTranscriptionViewModel.toggleLiveCoach()` (rangé dans prefs.json) ;
/// `liveCoachServiceProvider` (keepAlive, lib/core/providers/services/
/// live_coach.service.provider.dart) construit sur `resolveLiveAnswerModel`,
/// démarré/arrêté avec l'enregistrement quand l'interrupteur est activé,
/// nourri par `finalizedSegmentsStream`.
void main() {
  late LiveServiceHarness live;
  late AppDatabase db;
  late RecordingHttpAdapter http;
  late ProviderContainer c;

  const String claudeKey = 'sk-ant-test-SECRET-0123456789';

  Future<void> launch({required bool cloud, Duration? interval}) async {
    resetPrefs();
    await PrefsStore().update(<String, Object?>{
      LlmSettings.providerKey: LlmProviderId.anthropic.name,
      LlmSettings.cloudAllowedKey: cloud,
    });
    live = LiveServiceHarness(FakeAsync());
    db = memoryDatabase();
    http = RecordingHttpAdapter(
      reply: BodyReply(200, streamOf(LlmProviderId.anthropic, '{}')),
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
            LlmProviderId.anthropic: claudeKey,
          }),
        ),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
        // Même service, même modèle résolu ; seul l'écart entre deux lots
        // est raccourci, pour ne pas attendre 20 s.
        if (interval != null)
          liveCoachServiceProvider.overrideWith(
            (Ref ref) => LiveCoachService(
              resolveModel: () => resolveLiveAnswerModel(ref),
              interval: interval,
            ),
          ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
  }

  LiveTranscriptionViewModel vm() =>
      c.read(liveTranscriptionViewModelProvider.notifier);
  LiveCoachService coach() => c.read(liveCoachServiceProvider);

  /// Démarre une note ; [liveCoach] : interrupteur activé avant.
  Future<String> startRecording({required bool liveCoach}) async {
    vm();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (liveCoach) vm().toggleLiveCoach();
    await vm().startSession();
    return live.transcription.currentSessionStream.value!.id;
  }

  /// L'utilisateur dit [text] ; attendu comme segment de la note.
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

  bool sentAnywhere(String text) => http.bodies.any(
    (Map<String, dynamic>? b) => jsonEncode(b).contains(text),
  );

  group('interrupteur', () {
    test(
      'coupé par défaut ; activé, il l\'est encore au lancement suivant',
      () async {
        await launch(cloud: true);
        vm();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          c.read(liveTranscriptionViewModelProvider).isLiveCoachEnabled,
          isFalse,
        );

        vm().toggleLiveCoach();
        // Choix LLM déjà rangés (2 clés) : attendre celle de l'interrupteur.
        await eventually(() => expect(readPrefs().length, greaterThan(2)));

        final ProviderContainer again = ProviderContainer(
          overrides: <Override>[
            liveTranscriptionServiceProvider.overrideWithValue(
              LiveServiceHarness(FakeAsync()).service,
            ),
            processManagerServiceProvider.overrideWithValue(
              ProcessManagerService(channel: live.process),
            ),
            audioCaptureChannelProvider.overrideWithValue(
              DevicesAudioChannel(),
            ),
            apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
          ],
        );
        addTearDown(again.dispose);
        again.read(liveTranscriptionViewModelProvider);
        await eventually(
          () => expect(
            again.read(liveTranscriptionViewModelProvider).isLiveCoachEnabled,
            isTrue,
          ),
        );
      },
    );

    test('coupé : la phrase de l\'utilisateur ne part pas au coach (seule '
        'la question des autres part)', () async {
      await launch(cloud: true);
      await startRecording(liveCoach: false);

      await userSays('I am agree with you on this point.');
      live.fakeRemote.emitDone(
        AudioSource.output,
        'Quand est-ce que vous livrez le lot 1 ?',
      );
      await eventually(() => expect(http.requests, isNotEmpty));

      expect(http.requests, hasLength(1));
      expect(sentAnywhere('Quand est-ce que vous livrez'), isTrue);
    });
  });

  group('activé', () {
    test('Claude configuré et autorisé : la phrase anglaise de '
        'l\'utilisateur part chez Claude, pendant la réunion', () async {
      await launch(cloud: true);
      await startRecording(liveCoach: true);

      await userSays('I am agree with you on this point.');
      await eventually(
        () =>
            expect(sentAnywhere('I am agree with you on this point.'), isTrue),
      );

      expect(
        http.requests.map((RequestOptions r) => r.uri.host).toSet(),
        <String>{kProviderHost[LlmProviderId.anthropic]!},
      );
    });

    test(
      'envoi coupé (clé présente, modèle local installé) : rien ne part, '
      'ni chez Claude ni au modèle local ; le coach se dit indisponible',
      () async {
        await launch(cloud: false);
        await startRecording(liveCoach: true);

        await userSays('I am agree with you on this point.');
        await eventually(() => expect(coach().snapshot.unavailable, isTrue));

        expect(http.requests, isEmpty);
      },
    );

    test(
      'envoi coupé en pleine réunion : le lot suivant ne part pas',
      () async {
        await launch(cloud: true, interval: const Duration(milliseconds: 50));
        await startRecording(liveCoach: true);
        await userSays('I am agree with you on this point.');
        await eventually(() => expect(http.requests, hasLength(1)));

        await PrefsStore().update(<String, Object?>{
          LlmSettings.cloudAllowedKey: false,
        });
        await userSays('He have sent the deck to the client.');
        await eventually(() => expect(coach().snapshot.unavailable, isTrue));

        expect(http.requests, hasLength(1));
        expect(sentAnywhere('He have sent the deck'), isFalse);
      },
    );

    test(
      'une phrase dictée pendant la réunion n\'atteint jamais le coach',
      () async {
        await launch(cloud: true);
        await startRecording(liveCoach: true);
        final List<String> dictated = <String>[];
        final int pressAt = DateTime.now().millisecondsSinceEpoch;
        final MeetingDictation d = live.service.beginDictation()!;
        d.onText = (String text, bool _) => dictated.add(text);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        live.fakeRemote.emitDone(
          AudioSource.input,
          'DICTATED please remind the supplier about the invoice.',
          window: UtteranceWindow(startMs: pressAt + 50, endMs: pressAt + 90),
        );
        await eventually(() => expect(dictated, isNotEmpty));
        d.release();

        await userSays('I am agree with you on this point.');
        await eventually(
          () => expect(sentAnywhere('I am agree with you'), isTrue),
        );

        expect(sentAnywhere('DICTATED'), isFalse);
      },
    );

    test(
      'modèle muet : la transcription continue et Arrêter se termine',
      () async {
        await launch(cloud: true);
        http.reply = const HangReply();
        await startRecording(liveCoach: true);
        await userSays('I am agree with you on this point.');
        await eventually(() => expect(http.requests, isNotEmpty));

        await userSays('He have sent the deck to the client.');
        final String? id = await vm().stopSession();

        expect(id, isNotNull);
      },
    );

    test('Arrêter (coach d\'après l\'appel coupé) : ce que le direct a trouvé '
        'est rangé dans la note', () async {
      await launch(cloud: true);
      http.reply = BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, jsonEncode(kFeedbackJson)),
      );
      final String sessionId = await startRecording(liveCoach: true);
      await userSays('I am agree with you on this point.');
      await eventually(() => expect(coach().snapshot.corrections, isNotEmpty));

      await vm().stopSession();

      final EnglishFeedbackEntity? saved = SessionAnalysis.fromStored(
        (await SummaryDao(db).getBySessionId(sessionId))?.content,
      ).feedback;
      expect(saved?.corrections.single.corrected, 'I agree');
    });
  });
}
