import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/data/datasource/transcription.remote.data_source.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/diarization.service.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/core/providers/services/gap_backfill_retry.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/dictation_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';
import '../../helpers/voiced_pcm.dart';

// Product decision (2026-11-25): Oats keeps NO meeting audio, only complete
// transcripts. A session's files in the recordings folder
// (`<id>_mic.wav`, `<id>_system.wav`, `<id>_dictations.json`,
// `<id>_mic.nodictation.wav`) are a temporary safety net: they are deleted
// as soon as the note's processing ends, whatever the outcome. A passage
// that could not be recovered stays under its gap marker (never removed,
// never invented).
//
// App chain: real kernel, live view model, live service, gap backfill and
// its retry, launch repair. Fakes: processes, microphone, shortcut, text
// output, realtime source, HTTP (Mistral online engine, never the real API,
// no local socket), Ollama, database, and the post-call pass.
//
// The post-call pass (diarization script) is faked at
// `DiarizationService.processSession`: there is no process-runner seam in
// `DiarizationService`. The fake never deletes anything; it only does what
// the real pass does to its input (`micInputWithoutDictation`, which writes
// the muted copy when the meeting had a dictation), then succeeds, fails
// (script error: null) or crashes (throws). Removing the session's files is
// therefore the job of whoever ends the note's processing.
void main() {
  late Directory recordings;

  setUp(() async {
    recordings = Directory(LiveTranscriptionService.recordingsDir);
    expect(recordings.path, startsWith(Directory.systemTemp.path));
    if (recordings.existsSync()) await recordings.delete(recursive: true);
    await recordings.create(recursive: true);
  });

  /// Every file of [sessionId] left in the recordings folder.
  List<String> filesOf(String sessionId) =>
      recordings
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String name) => name.startsWith('${sessionId}_'))
          .toList()
        ..sort();

  Future<void> expectNoAudioLeft(String sessionId) => eventually(
    () => expect(
      filesOf(sessionId),
      isEmpty,
      reason: 'the note is done: none of its audio may stay on disk',
    ),
    timeout: const Duration(seconds: 5),
  );

  test('normal stop, post-call pass succeeds: no audio file of the session '
      'remains', () async {
    final _App app = _App(pass: _PassOutcome.succeeds);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();

    final String id = await app.recordNote();
    expect(filesOf(id), contains('${id}_mic.wav'), reason: 'precondition');
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[id]));
    expect(app.pass.sawAudio, <bool>[true], reason: 'the pass got the audio');

    await expectNoAudioLeft(id);
  });

  test('stop, post-call pass fails (diarization script error): no audio file '
      'remains and the transcript is intact', () async {
    final _App app = _App(pass: _PassOutcome.fails);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();

    final String id = await app.recordNote();
    expect(filesOf(id), contains('${id}_mic.wav'), reason: 'precondition');
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[id]));
    expect(app.pass.sawAudio, <bool>[true], reason: 'the pass got the audio');

    expect(await app.lines(id), contains(_App.spoken), reason: 'transcript');
    await expectNoAudioLeft(id);
    expect(await app.lines(id), contains(_App.spoken), reason: 'transcript');
  });

  test('stop, post-call pass crashes (throws): no audio file remains and the '
      'transcript is intact', () async {
    final _App app = _App(pass: _PassOutcome.throws);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();

    final String id = await app.recordNote();
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[id]));
    expect(app.pass.sawAudio, <bool>[true], reason: 'the pass got the audio');

    expect(await app.lines(id), contains(_App.spoken), reason: 'transcript');
    await expectNoAudioLeft(id);
  });

  test('stop with a gap marker the backfill cannot recover (transcriber '
      'unavailable): no audio file remains, the marker stays, and no retry '
      'waits on the deleted audio', () async {
    final _App app = _App(pass: _PassOutcome.succeeds);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();
    app.http.transcriberDown = true;

    final String id = await app.recordNote(gap: true);
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[id]));
    expect(app.pass.sawAudio, <bool>[true], reason: 'the pass got the audio');

    expect(app.http.transcriptions, isNotEmpty, reason: 'backfill was tried');
    expect(await app.markers(id), hasLength(1), reason: 'marker kept');
    await expectNoAudioLeft(id);

    // Later: the transcriber is back, the app retries what is pending (as
    // when the server is ready, and at next launch). Nothing waits on this
    // session any more: no request, no error, the marker is unchanged.
    app.http.transcriberDown = false;
    final int requests = app.http.transcriptions.length;
    await app.container.read(gapBackfillRetryProvider).retryPending();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.http.transcriptions, hasLength(requests));
    expect(await app.markers(id), hasLength(1), reason: 'never invented');
  });

  test('stop with a gap marker, server busy because a new recording started: '
      'once the note is done its audio is gone and its marker stays, the new '
      'recording keeps its own audio', () async {
    final _App app = _App(pass: _PassOutcome.succeeds);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();
    app.http.transcriberDown = true;
    final Completer<void> passGate = app.pass.gate = Completer<void>();

    final String first = await app.recordNote(gap: true);
    await app.stop();
    await eventually(() => expect(app.pass.started, <String>[first]));

    // The user starts the next meeting while the first note is processed.
    final Future<void> next = app.vm.startSession();
    passGate.complete();
    await next;
    final String second = app.currentSessionId;
    expect(second, isNot(first));
    await eventually(() => expect(app.pass.finished, <String>[first]));

    expect(await app.markers(first), hasLength(1), reason: 'marker kept');
    await expectNoAudioLeft(first);
    expect(
      filesOf(second),
      contains('${second}_mic.wav'),
      reason: 'the recording in progress keeps its audio',
    );

    // The new meeting ends with the transcriber back: the first note is
    // not retried on deleted audio, its marker stays.
    app.http.transcriberDown = false;
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[first, second]));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await app.markers(first), hasLength(1), reason: 'never invented');
    expect(filesOf(first), isEmpty);
  });

  test('app killed during a meeting: at next launch the repair and its '
      'backfill run on the audio, then no audio file of the session '
      'remains', () async {
    final _App app = _App(pass: _PassOutcome.succeeds);
    addTearDown(app.dispose);
    await app.writePrefs();
    // What the killed app left: a session still `active`, its mic WAV
    // (10 s of speech, never transcribed) and a dictation interval.
    final String id = '${DateTime.now().millisecondsSinceEpoch - 3600000}';
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(int.parse(id));
    await app.container
        .read(sessionRepositoryProvider)
        .create(
          SessionEntity(
            id: id,
            title: 'Killed meeting',
            createdAt: at,
            updatedAt: at,
            status: SessionStatus.active,
          ),
        );
    final WavRecorder wav = WavRecorder();
    await wav.open('${recordings.path}/${id}_mic.wav');
    await wav.append(voicedPcm(10 * 32000));
    await wav.close();
    DictatedIntervalsStore(
      recordings.path,
    ).add(id, const DictatedInterval(startMs: 9000, endMs: 10000));
    expect(filesOf(id), <String>['${id}_dictations.json', '${id}_mic.wav']);

    await app.launch();

    await eventually(
      () => expect(app.http.transcriptions, isNotEmpty),
      timeout: const Duration(seconds: 5),
    );
    await eventually(
      () async => expect(await app.lines(id), contains('Retrouvé.')),
      timeout: const Duration(seconds: 5),
    );
    await expectNoAudioLeft(id);
  });

  test('a dictation during the meeting: its dictations file and the muted '
      'copy of the mic are gone too', () async {
    final _App app = _App(pass: _PassOutcome.fails);
    addTearDown(app.dispose);
    await app.writePrefs();
    await app.launch();

    final String id = await app.recordNote(dictation: true);
    expect(
      filesOf(id),
      contains('${id}_dictations.json'),
      reason: 'precondition: the dictation was noted',
    );
    await app.stop();
    await eventually(() => expect(app.pass.finished, <String>[id]));
    expect(app.pass.sawAudio, <bool>[true], reason: 'the pass got the audio');
    expect(app.pass.mutedCopies, <String>[
      '${id}_mic.nodictation.wav',
    ], reason: 'precondition: the pass got the muted copy');

    await expectNoAudioLeft(id);
  });

  test('beyond the five cases: English coach off, so no post-call pass runs; '
      'no audio file remains once the note is stopped', () async {
    final _App app = _App(pass: _PassOutcome.succeeds);
    addTearDown(app.dispose);
    await app.writePrefs(coach: false);
    await app.launch();

    final String id = await app.recordNote();
    expect(filesOf(id), contains('${id}_mic.wav'), reason: 'precondition');
    await app.stop();

    expect(await app.lines(id), contains(_App.spoken), reason: 'transcript');
    await expectNoAudioLeft(id);
    expect(app.pass.started, isEmpty, reason: 'no post-call pass');
  });
}

enum _PassOutcome { succeeds, fails, throws }

/// Post-call pass without any process. Never deletes a file.
final class _FakePostCallPass extends DiarizationService {
  _FakePostCallPass(this.outcome);

  final _PassOutcome outcome;
  final List<String> started = <String>[];
  final List<String> finished = <String>[];
  final List<String> mutedCopies = <String>[];

  /// Whether the session's mic WAV was there when each pass started.
  final List<bool> sawAudio = <bool>[];

  /// Holds the pass until completed (a long pass).
  Completer<void>? gate;

  @override
  Future<DiarizationResult?> processSession(String sessionId) async {
    started.add(sessionId);
    sawAudio.add(File(micWavPath(sessionId)).existsSync());
    try {
      // What the real pass feeds the script: the mic without dictated words.
      final String input = await micInputWithoutDictation(sessionId);
      if (input != micWavPath(sessionId) && File(input).existsSync()) {
        mutedCopies.add(File(input).uri.pathSegments.last);
      }
      await gate?.future;
      switch (outcome) {
        case _PassOutcome.succeeds:
          return const DiarizationResult(micText: _App.spoken);
        case _PassOutcome.fails:
          return null;
        case _PassOutcome.throws:
          throw const ProcessException('uv', <String>[], 'script crashed');
      }
    } finally {
      finished.add(sessionId);
    }
  }
}

/// Mistral batch API: a sentence per transcription, or 503 while
/// [transcriberDown]; anything else (coach) is refused. Nothing leaves the
/// machine.
final class _MistralHttp implements HttpClientAdapter {
  final List<Uri> requests = <Uri>[];
  bool transcriberDown = false;

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
    if (transcriberDown) return ResponseBody.fromString('{}', 503);
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

final class _App {
  _App({required _PassOutcome pass}) : pass = _FakePostCallPass(pass) {
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
            LlmProviderId.mistral: 'mistral-test-SECRET-0123456789',
          }),
        ),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
        transcriptionRemoteDataSourceProvider.overrideWithValue(remote),
        diarizationServiceProvider.overrideWithValue(this.pass),
      ],
    );
  }

  static const String spoken = 'Bonjour à tous.';

  final _FakePostCallPass pass;
  late final AppDatabase db;
  late final ProviderContainer container;
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final FakeGlobalShortcutChannel shortcuts = FakeGlobalShortcutChannel();
  final FakeTextOutputChannel output = FakeTextOutputChannel();
  final FakeTranscriptionRemoteDataSource remote =
      FakeTranscriptionRemoteDataSource();
  final _MistralHttp http = _MistralHttp();

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }

  /// prefs.json: online engine (Mistral, no local server or socket), post-
  /// call pass through the English coach, dictation on, live speakers off.
  Future<void> writePrefs({bool coach = true}) async {
    resetPrefs();
    await PrefsStore().update(<String, Object?>{
      TranscriptionEngineSettings.engineKey: TranscriptionEngine.mistral.name,
      LlmSettings.cloudAllowedKey: true,
      'coach_enabled': coach,
      'live_speakers_enabled': false,
    });
    await DictationPreferences().save(
      const DictationSettings(outputMode: DictationOutputMode.clipboard),
    );
  }

  /// App launch: kernel (launch repair, pending backfills), dictation.
  Future<void> launch() async {
    await container.read(kernelProvider.future);
    await eventually(() => expect(shortcuts.registered, isNotEmpty));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  LiveTranscriptionViewModel get vm =>
      container.read(liveTranscriptionViewModelProvider.notifier);

  LiveTranscriptionService get live =>
      container.read(liveTranscriptionServiceProvider);

  String get currentSessionId => live.currentSessionStream.value!.id;

  /// A meeting: 3 s of speech and one transcribed sentence; with [gap], a
  /// lost passage (its marker); with [dictation], a held shortcut in the
  /// middle. Still recording when it returns.
  Future<String> recordNote({bool gap = false, bool dictation = false}) async {
    vm;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await vm.startSession();
    final String id = currentSessionId;
    final int t0 =
        live.currentSessionStream.value!.createdAt.millisecondsSinceEpoch;
    MeetingDictation? held;
    for (int n = 0; n < 30; n++) {
      if (dictation && n == 10) held = live.beginDictation();
      if (dictation && n == 20) held?.release();
      audio.emit(chunk(AudioSource.input, n, timestampMs: t0 + n * 100));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    remote.emitDone(AudioSource.input, spoken);
    if (gap) {
      remote.emitGap(
        AudioGap(source: AudioSource.input, startMs: t0, endMs: t0 + 3000),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (dictation) expect(held, isNotNull, reason: 'dictation began');
    if (gap) expect(await markers(id), hasLength(1), reason: 'marker written');
    return id;
  }

  /// Stop button.
  Future<void> stop() => vm.stopSession();

  Future<List<TranscriptSegmentEntity>> _segments(String id) =>
      container.read(transcriptRepositoryProvider).getBySessionId(id);

  /// The note's lines, in order.
  Future<List<String>> lines(String id) async => <String>[
    for (final TranscriptSegmentEntity s in await _segments(id)) s.text,
  ];

  /// The note's gap markers.
  Future<List<String>> markers(String id) async => <String>[
    for (final String line in await lines(id))
      if (line.startsWith(LiveTranscriptionService.gapMarkerPrefix)) line,
  ];
}
