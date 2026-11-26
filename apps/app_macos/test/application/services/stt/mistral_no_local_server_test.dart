import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/database/app_database.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/data/datasource/transcription.remote.data_source.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/diarization.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/local_model_fakes.dart';
import '../../../helpers/settings_fakes.dart';

// L'utilisateur a choisi Mistral pour que son Mac ne fasse plus tourner le
// modèle local de 7 Go. Besoin : avec le moteur en ligne (choisi, envoi
// permis, clé rangée), RIEN ne démarre le serveur local : ni le lancement de
// l'app, ni une note (enregistrée, arrêtée), ni la passe post-session, ni le
// rattrapage d'un repère, ni une dictée, ni un serveur local qui tombe en
// pleine note.
//
// Chaîne de l'app : vrais providers (kernel, view model du direct, service
// du direct, contrôleur de dictée, rattrapage) ; faux : processus, micro,
// raccourci, sortie de texte, source temps réel, HTTP (jamais l'API
// réelle), diarization (jamais `uv run`), Ollama, base.
// Les appelants de `startServer` : DictationController (`_warmServer` au
// lancement et après la passe post-session, `_awaitServer` à l'appui,
// `downloadModel`), LiveTranscriptionService (démarrage de note,
// `_restartServer` quand le serveur tombe).

const String _key = 'mistral-test-SECRET-0123456789';

/// Mistral batch : chaque transcription rend une phrase ; le reste (coach)
/// est refusé. Aucune requête ne quitte la machine.
final class _MistralHttp implements HttpClientAdapter {
  final List<Uri> requests = <Uri>[];

  Iterable<Uri> get transcriptions =>
      requests.where((Uri u) => u.path.contains('audio/transcriptions'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    await requestStream?.drain<void>();
    if (!options.uri.path.contains('audio/transcriptions')) {
      return ResponseBody.fromString('{}', 500);
    }
    return ResponseBody.fromString(
      jsonEncode(<String, Object>{
        'text': 'Retrouvé.',
        'segments': <Object>[
          <String, Object>{'start': 0.0, 'end': 1.0, 'text': 'Retrouvé.'},
        ],
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Passe post-session sans processus : comptée, sans résultat.
final class _NoDiarization extends DiarizationService {
  int calls = 0;

  @override
  Future<DiarizationResult?> processSession(String sessionId) async {
    calls++;
    return null;
  }
}

final class _App {
  _App({required this.mistral}) {
    db = memoryDatabase();
    container = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: false)),
        processManagerChannelProvider.overrideWithValue(process),
        audioCaptureChannelProvider.overrideWithValue(audio),
        globalShortcutChannelProvider.overrideWithValue(shortcuts),
        textOutputChannelProvider.overrideWithValue(output),
        apiKeyStoreProvider.overrideWithValue(
          InMemoryApiKeyStore(<LlmProviderId, String>{
            LlmProviderId.mistral: _key,
          }),
        ),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
        transcriptionRemoteDataSourceProvider.overrideWithValue(remote),
        diarizationServiceProvider.overrideWithValue(diarization),
      ],
    );
  }

  final bool mistral;
  late final AppDatabase db;
  late final ProviderContainer container;
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final FakeGlobalShortcutChannel shortcuts = FakeGlobalShortcutChannel();
  final FakeTextOutputChannel output = FakeTextOutputChannel();
  final FakeTranscriptionRemoteDataSource remote =
      FakeTranscriptionRemoteDataSource();
  final _MistralHttp http = _MistralHttp();
  final _NoDiarization diarization = _NoDiarization();

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }

  /// prefs.json : moteur, envoi en ligne permis, coach (passe post-session)
  /// et dictée activés ; interlocuteurs en direct coupés (processus réel).
  Future<void> writePrefs() async {
    resetPrefs();
    await PrefsStore().update(<String, Object?>{
      if (mistral)
        TranscriptionEngineSettings.engineKey: TranscriptionEngine.mistral.name,
      LlmSettings.cloudAllowedKey: true,
      'coach_enabled': true,
      'live_speakers_enabled': false,
    });
    await DictationPreferences().save(
      const DictationSettings(outputMode: DictationOutputMode.clipboard),
    );
  }

  /// Lancement de l'app : kernel, dictée appliquée.
  Future<void> launch() async {
    await container.read(kernelProvider.future);
    await eventually(() => expect(shortcuts.registered, isNotEmpty));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  LiveTranscriptionViewModel get vm =>
      container.read(liveTranscriptionViewModelProvider.notifier);

  /// Une note : 3 s de parole, un repère de perte (rattrapé à l'arrêt, en
  /// ligne seulement), arrêt, passe post-session finie.
  Future<void> recordNote({void Function()? whileRecording}) async {
    vm;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await vm.startSession();
    whileRecording?.call();
    final int t0 = container
        .read(liveTranscriptionServiceProvider)
        .currentSessionStream
        .value!
        .createdAt
        .millisecondsSinceEpoch;
    for (int id = 0; id < 30; id++) {
      audio.emit(chunk(AudioSource.input, id, timestampMs: t0 + id * 100));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Moteur local : pas de repère, son rattrapage viserait le port local.
    if (mistral) {
      remote.emitGap(
        AudioGap(source: AudioSource.input, startMs: t0, endMs: t0 + 3000),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await vm.stopSession();
    await eventually(() => expect(diarization.calls, 1));
    // Le prêt du serveur rend la main après la passe (relance éventuelle).
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// Une dictée hors réunion : appui, 2 s de parole, relâchement.
  Future<void> dictate() async {
    shortcuts.emit(ShortcutEvent.pressed);
    await Future<void>.delayed(Duration.zero);
    for (int id = 0; id < 20; id++) {
      audio.emit(chunk(AudioSource.input, id, timestampMs: 1000000 + id * 100));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    shortcuts.emit(ShortcutEvent.released);
    await eventually(
      () => expect(
        container.read(dictationControllerProvider).state,
        isNot(
          anyOf(
            isA<DictationStarting>(),
            isA<DictationListening>(),
            isA<DictationTranscribing>(),
          ),
        ),
      ),
      timeout: const Duration(seconds: 5),
    );
  }
}

void main() {
  test('moteur Mistral : lancement, note enregistrée puis arrêtée, passe '
      'post-session, rattrapage d un repère et dictée ne démarrent jamais le '
      'serveur local', () async {
    final _App app = _App(mistral: true);
    addTearDown(app.dispose);
    await app.writePrefs();

    await app.launch();
    expect(app.process.starts, isEmpty, reason: 'lancement');

    await app.recordNote();
    expect(app.remote.connectedUrls, <String>[
      MistralRealtimeClient.url,
    ], reason: 'la note est bien en ligne');
    expect(app.http.transcriptions, isNotEmpty, reason: 'rattrapage en ligne');
    expect(app.process.starts, isEmpty, reason: 'note et passe post-session');

    await app.dictate();
    expect(app.output.copies, <String>['Retrouvé.'], reason: 'dictée en ligne');

    expect(app.process.starts, isEmpty);
  });

  // Prix de la transcription en ligne (2026-11-26), branchement des
  // providers : à l'arrêt, l'audio temps réel rendu par la source distante
  // (`takeSentAudioMs`) est rangé dans la note, et le rattrapage du repère
  // par Mistral batch y ajoute son audio (réponse sans `usage` : la
  // longueur du PCM envoyé). Lu en SQL brut (colonnes du schéma v4).
  test('moteur Mistral : la note arrêtée garde son audio temps réel et celui '
      'du rattrapage (branchement des providers)', () async {
    final _App app = _App(mistral: true);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();

    await app.recordNote(whileRecording: () => app.remote.sentAudioMs = 5000);
    expect(app.http.transcriptions, isNotEmpty, reason: 'rattrapage en ligne');

    final Map<String, Object?> row =
        (await app.db
                .customSelect(
                  'SELECT cloud_realtime_ms, cloud_batch_ms FROM sessions',
                )
                .getSingle())
            .data;
    expect(row['cloud_realtime_ms'], 5000);
    expect(row['cloud_batch_ms'], greaterThan(0));
  });

  test('garde : même chaîne avec le moteur local, la passe post-session '
      'relance le serveur local (le faux voit bien les démarrages)', () async {
    final _App app = _App(mistral: false);
    addTearDown(app.dispose);
    await app.writePrefs();

    await app.launch();
    await app.recordNote();

    expect(
      app.remote.connectedUrls,
      isNot(contains(MistralRealtimeClient.url)),
    );
    await eventually(
      () => expect(app.process.starts, hasLength(greaterThanOrEqualTo(2))),
    );
  });

  test('moteur Mistral : un serveur local qui tombe pendant la note n est pas '
      'relancé', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async);
      unawaited(
        h.service.startTranscription(
          serverCommand: LiveServiceHarness.command,
          serverArgs: LiveServiceHarness.args,
          engine: TranscriptionEngine.mistral,
        ),
      );
      async.elapse(const Duration(seconds: 1));

      h.process.crash(); // voxmlx d'avant, encore là, qui meurt
      async.elapse(const Duration(minutes: 2));

      expect(h.process.starts, isEmpty);
    });
  });
}
