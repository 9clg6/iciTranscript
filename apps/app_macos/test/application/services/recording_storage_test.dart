import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/services/transcription.service.dart';
import 'package:core_domain/domain/usecases/save_transcript_segment.use_case.dart';
import 'package:core_domain/domain/usecases/start_session.use_case.dart';
import 'package:core_domain/domain/usecases/stop_session.use_case.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../helpers/live_service_fakes.dart';

// Place disque pendant une note (le Mac de l'utilisateur : 4,9 Go libres).
// Rien ne vérifie la place avant ni pendant une réunion ; une écriture WAV
// ratée ne se voit qu'à la fermeture ; une phrase qui ne se range pas
// (disque plein, erreur SQLite) disparaît de l'écran et n'est pas
// réessayée (`TranscriptionService.saveSegment` rend faux, journalisé ;
// seuls les repères ont `_saveWithRetry`, 5 essais puis abandon).
//
// RÈGLES CHOISIES (un seul endroit : `RecordingStorage`) :
// - « peu de place » : moins de 2 h d'enregistrement possibles, calculées
//   sur les sources réellement enregistrées (PCM16 16 kHz : 32 000 o/s par
//   source ; micro + son du Mac = 64 000 o/s, 2 h ≈ 460 Mo). Une règle en
//   TEMPS dit à l'utilisateur ce qui compte : « ma réunion tiendra-t-elle ? »
//   ; un seuil fixe de 2 Go préviendrait trop tôt (8 h de micro) ;
// - « critique » : moins de 200 Mo libres (≈ 52 min à deux sources) : macOS
//   et SQLite commencent à manquer de place, erreur claire ;
// - contrôle avant le départ, puis toutes les 30 s pendant la note (30 s à
//   deux sources = 1,9 Mo : la règle ne peut pas être franchie de beaucoup
//   entre deux contrôles).
//
// API supposée :
// - lib/application/services/recording_storage.dart : `enum StorageLevel
//   { ok, low, critical }` ; `RecordingStorage { StorageLevel level;
//   Duration? recordingTimeLeft; bool audioCopyFailing; int unsavedLines }`
//   et ses constantes `lowRecordingTime` (2 h), `criticalBytes`
//   (200 000 000), `checkEvery` (30 s), `bytesPerSourceSecond` (32 000) ;
// - `LiveTranscriptionService(..., Future<int?> Function()? freeBytes)` ;
//   `storageStream` (valeur courante + changements) ;
// - `WavRecorder.writeErrors` / `failing` / `missing`
//   (wav_recorder_disk_full_test.dart) ;
// - `LiveTranscriptionService.noAudioCopyMarkerText(startMs, endMs)` et
//   `isNoAudioCopyMarker(text)` : repère « pas de copie audio » dans la
//   note pour l'intervalle que le rattrapage ne pourra pas couvrir.
const int _mb = 1000 * 1000;

/// Enregistreur WAV factice qui peut rater ses écritures.
final class _Wav extends WavRecorder {
  String? path;
  int bytes = 0;
  int chunks = 0;
  bool closed = false;

  @override
  bool get isOpen => path != null && !closed;

  @override
  Future<void> open(String path) async => this.path = path;

  @override
  Future<void> close() async => closed = true;

  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  bool full = false;
  final List<({int startMs, int endMs})> _missing =
      <({int startMs, int endMs})>[];
  int? _failedAt;

  @override
  Stream<Object> get writeErrors => _errors.stream;

  @override
  bool get failing => full;

  @override
  List<({int startMs, int endMs})> get missing => _missing;

  @override
  Future<void> append(Uint8List pcm) async {
    if (!isOpen) return;
    final int atMs = bytes ~/ 32;
    if (full) {
      if (_failedAt == null) {
        _failedAt = atMs;
        _errors.add(const FileSystemException('No space left on device'));
      }
    } else if (_failedAt != null) {
      _missing.add((startMs: _failedAt!, endMs: atMs));
      _failedAt = null;
    }
    bytes += pcm.length;
    chunks++;
  }
}

/// Service réel sur les faux, avec une sonde de place libre réglable et des
/// WAV factices qui peuvent rater.
final class _Rig {
  _Rig(this.async, {required this.free}) {
    transcription = TranscriptionService(
      startSessionUseCase: StartSessionUseCase(sessionRepository: sessions),
      stopSessionUseCase: StopSessionUseCase(sessionRepository: sessions),
      saveTranscriptSegmentUseCase: SaveTranscriptSegmentUseCase(
        transcriptRepository: segments,
      ),
    );
    service = LiveTranscriptionService(
      processManagerService: ProcessManagerService(channel: process),
      audioCaptureChannel: audio,
      transcriptionRemoteDataSource: remote,
      transcriptionService: transcription,
      createWavRecorder: () {
        final _Wav w = _Wav();
        wavs.add(w);
        return w;
      },
      freeBytes: () async {
        probes.add(async.elapsed);
        return free;
      },
    );
    service.storageStream.listen(states.add);
  }

  final FakeAsync async;
  int free;
  final List<Duration> probes = <Duration>[];
  final List<RecordingStorage> states = <RecordingStorage>[];
  final FakeProcessManagerChannel process = FakeProcessManagerChannel();
  final FakeAudioCaptureChannel audio = FakeAudioCaptureChannel();
  final FakeTranscriptionRemoteDataSource remote =
      FakeTranscriptionRemoteDataSource();
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  final InMemoryTranscriptRepository segments = InMemoryTranscriptRepository();
  final List<_Wav> wavs = <_Wav>[];
  late final TranscriptionService transcription;
  late final LiveTranscriptionService service;

  RecordingStorage get storage => states.last;

  int get t0 => transcription
      .currentSessionStream
      .value!
      .createdAt
      .millisecondsSinceEpoch;

  void start({bool outputEnabled = true}) {
    unawaited(
      service.startTranscription(
        outputEnabled: outputEnabled,
        serverCommand: LiveServiceHarness.command,
        serverArgs: LiveServiceHarness.args,
      ),
    );
    async.elapse(const Duration(seconds: 1));
  }

  int _id = 0;

  /// [seconds] s de parole des deux sources.
  void speak(int seconds) {
    for (int i = 0; i < seconds * 10; i++, _id++) {
      for (final AudioSource s in AudioSource.values) {
        audio.emit(chunk(s, _id, timestampMs: t0 + _id * 100));
      }
      async.elapse(const Duration(milliseconds: 100));
    }
  }
}

/// Place libre pour [d] d'enregistrement à deux sources.
int _forTime(Duration d) =>
    d.inSeconds * 2 * RecordingStorage.bytesPerSourceSecond;

void main() {
  test('les règles sont posées en un seul endroit', () {
    expect(RecordingStorage.lowRecordingTime, const Duration(hours: 2));
    expect(RecordingStorage.criticalBytes, 200 * _mb);
    expect(RecordingStorage.checkEvery, const Duration(seconds: 30));
    expect(RecordingStorage.bytesPerSourceSecond, 32000);
  });

  group('avant la note', () {
    test('peu de place : la note démarre quand même, l avertissement dit le '
        'temps d enregistrement restant', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: _forTime(const Duration(minutes: 90)));
        r.start();
        expect(r.service.isRunning, isTrue, reason: 'départ permis');
        expect(r.storage.level, StorageLevel.low);
        expect(
          (r.storage.recordingTimeLeft! - const Duration(minutes: 90)).inSeconds
              .abs(),
          lessThanOrEqualTo(60),
        );
      });
    });

    test('micro seul : le temps restant compte une source', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: _forTime(const Duration(minutes: 90)));
        r.start(outputEnabled: false);
        expect(r.storage.level, StorageLevel.ok, reason: '3 h de micro');
        expect(
          (r.storage.recordingTimeLeft! - const Duration(minutes: 180))
              .inSeconds
              .abs(),
          lessThanOrEqualTo(60),
        );
      });
    });

    test('assez de place : aucun avertissement', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 50 * 1000 * _mb);
        r.start();
        expect(r.storage.level, StorageLevel.ok);
        expect(r.storage.audioCopyFailing, isFalse);
      });
    });
  });

  group('pendant la note', () {
    test('place contrôlée toutes les 30 s', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 50 * 1000 * _mb);
        r.start();
        final int before = r.probes.length;
        r.speak(300);
        expect(r.probes.length - before, inInclusiveRange(9, 11));
      });
    });

    test('le seuil franchi : avertissement en moins de 30 s ; sous 200 Mo : '
        'erreur claire', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 50 * 1000 * _mb);
        r.start();
        r.speak(10);
        r.free = _forTime(const Duration(minutes: 100));
        r.speak(31);
        expect(r.storage.level, StorageLevel.low);
        r.free = 150 * _mb;
        r.speak(31);
        expect(r.storage.level, StorageLevel.critical);
      });
    });

    test('la place revient : l avertissement disparaît', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 150 * _mb);
        r.start();
        expect(r.storage.level, StorageLevel.critical);
        r.free = 50 * 1000 * _mb;
        r.speak(31);
        expect(r.storage.level, StorageLevel.ok);
      });
    });
  });

  group('écriture WAV ratée', () {
    test('se voit tout de suite, pas à l arrêt', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 50 * 1000 * _mb);
        r.start();
        r.speak(5);
        for (final _Wav w in r.wavs) {
          w.full = true;
        }
        r.speak(1);
        expect(r.storage.audioCopyFailing, isTrue);
        expect(r.service.isRunning, isTrue, reason: 'la note continue');
      });
    });

    test('la note dit l intervalle sans copie audio, les phrases et les '
        'repères de perte continuent', () {
      fakeAsync((FakeAsync async) {
        final _Rig r = _Rig(async, free: 50 * 1000 * _mb);
        r.start();
        r.speak(5);
        for (final _Wav w in r.wavs) {
          w.full = true;
        }
        r.speak(10); // 5–15 s sans copie
        r.remote.emitDone(
          AudioSource.input,
          'Phrase dite pendant le disque plein.',
          window: UtteranceWindow(
            startMs: r.t0 + 8000,
            endMs: r.t0 + 11000,
            hadSpeech: true,
          ),
        );
        r.remote.emitGap(
          AudioGap(
            source: AudioSource.output,
            startMs: r.t0 + 9000,
            endMs: r.t0 + 12000,
          ),
        );
        for (final _Wav w in r.wavs) {
          w.full = false;
        }
        r.speak(5);
        expect(r.storage.audioCopyFailing, isFalse, reason: 'reprise');

        final List<TranscriptSegmentEntity> note = r.segments.store.values
            .toList();
        expect(
          note.map((TranscriptSegmentEntity s) => s.text),
          contains('Phrase dite pendant le disque plein.'),
        );
        expect(
          note.where(
            (TranscriptSegmentEntity s) =>
                s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          ),
          isNotEmpty,
          reason: 'le repère de perte est toujours écrit',
        );
        final List<TranscriptSegmentEntity> noCopy = note
            .where(
              (TranscriptSegmentEntity s) =>
                  LiveTranscriptionService.isNoAudioCopyMarker(s.text),
            )
            .toList();
        expect(noCopy, isNotEmpty, reason: 'la note dit : pas de copie audio');
        expect(
          noCopy.map((TranscriptSegmentEntity s) => s.text),
          contains(LiveTranscriptionService.noAudioCopyMarkerText(5000, 15000)),
        );
      });
    });
  });
}
