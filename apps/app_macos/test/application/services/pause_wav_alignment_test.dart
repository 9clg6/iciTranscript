import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Bug supposé (2026-11-25) : pendant une pause, rien n'est ajouté aux WAV de
// la session, mais les heures des lignes et des repères restent comptées
// depuis le début de la session (heure murale). Après une pause de P s,
// l'audio d'une heure H est donc à H − P dans le WAV, et tout ce qui lit le
// WAV à l'heure d'un repère (rattrapage des pertes, diarization d'après
// session, réparation au lancement) lit le mauvais audio.
//
// Rejeu : vrai `LiveTranscriptionService`, VRAI `WavRecorder` sur un disque
// en mémoire ; 10 s de parole, pause de 20 s (horloge factice), reprise,
// parole de 30 à 35 s ; la perte de 30–35 s arrive comme en direct (fenêtre
// perdue par la source distante) ; après l'arrêt, le vrai rattrapage lit le
// WAV avec un transcripteur qui dit ce qu'il entend : « Dit à N s. » pour
// l'audio capté à N s (numéro du chunk dans ses deux premiers échantillons).
//
// Attendu : la phrase dite à 30 s revient dans la note, une fois ; aucune
// phrase d'avant la pause n'est prise pour elle.

/// Disque en mémoire (lecture et écriture), assez pour le service, le
/// `WavRecorder` et le rattrapage.
final class _Disk {
  final Map<String, Uint8List> bytes = <String, Uint8List>{};

  R run<R>(R Function() body) => IOOverrides.runZoned(
    body,
    createFile: (String path) => _File(this, path),
    createDirectory: (String path) => _Dir(path),
  );
}

final class _File implements File {
  _File(this._disk, this.path);

  final _Disk _disk;

  @override
  final String path;

  @override
  Directory get parent => _Dir(path.substring(0, path.lastIndexOf('/')));

  @override
  bool existsSync() => _disk.bytes.containsKey(path);

  @override
  int lengthSync() => _disk.bytes[path]!.length;

  @override
  Future<int> length() async => lengthSync();

  @override
  Future<bool> exists() async => existsSync();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (mode == FileMode.write) _disk.bytes[path] = Uint8List(0);
    return _Raf(_disk, path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Raf implements RandomAccessFile {
  _Raf(this._disk, this._path);

  final _Disk _disk;
  final String _path;
  int _at = 0;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    final List<int> data = buffer.sublist(start, end);
    Uint8List b = _disk.bytes[_path]!;
    if (_at + data.length > b.length) {
      b = Uint8List(_at + data.length)..setRange(0, b.length, b);
    }
    b.setRange(_at, _at + data.length, data);
    _disk.bytes[_path] = b;
    _at += data.length;
    return this;
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    _at = position;
    return this;
  }

  @override
  Future<int> length() async => _disk.bytes[_path]!.length;

  @override
  Future<Uint8List> read(int count) async {
    final Uint8List b = _disk.bytes[_path]!;
    final int from = _at.clamp(0, b.length);
    final int end = (_at + count).clamp(0, b.length);
    final Uint8List out = Uint8List.fromList(b.sublist(from, end));
    _at = end;
    return out;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Dir implements Directory {
  _Dir(this.path);

  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) async => this;

  @override
  void createSync({bool recursive = false}) {}

  @override
  Directory createTempSync([String? prefix]) => _Dir('$path/${prefix ?? ''}0');

  @override
  Directory get absolute => this;

  @override
  bool existsSync() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Dit ce qu'il entend : « Dit à N s. » pour chaque chunk parlé capté à
/// N s pile (numéro de chunk multiple de 10).
final class _Listener implements PcmTranscriber {
  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final List<({int offsetMs, String text})> out =
        <({int offsetMs, String text})>[];
    for (int c = 0; (c + 1) * 3200 <= pcm.length; c++) {
      final Uint8List piece = Uint8List.sublistView(
        pcm,
        c * 3200,
        (c + 1) * 3200,
      );
      if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(piece)) continue;
      final ByteData d = ByteData.sublistView(piece);
      final int id =
          d.getInt16(0, Endian.little) + (d.getInt16(2, Endian.little) << 15);
      if (id % 10 == 0) {
        out.add((offsetMs: c * 100, text: 'Dit à ${id ~/ 10} s.'));
      }
    }
    return out;
  }
}

typedef _Run = ({
  List<String> note,
  bool markerStored,
  Duration? wavDuration,
  List<String> captureLog,
  Object? backfillError,
});

/// Réunion micro : parole 0–10 s, puis, si [pause], pause de 20 s et
/// reprise (sinon 20 s de silence capté), parole 30–35 s ; perte de
/// 30–35 s signalée en direct ; arrêt ; rattrapage sur le WAV laissé.
Future<_Run> _meeting({required bool pause}) async {
  final _Disk disk = _Disk();
  late InMemoryTranscriptRepository segments;
  late String sessionId;
  late List<String> captureLog;
  disk.run(() {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(
        async,
        createWavRecorder: WavRecorder.new,
      )..start(outputEnabled: false);
      void say(int id, {bool voiced = true}) {
        h.audio.emit(
          chunk(
            AudioSource.input,
            id,
            timestampMs: h.t0 + id * 100,
            voiced: voiced,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));
      }

      for (int id = 0; id < 100; id++) {
        say(id);
      }
      if (pause) {
        unawaited(h.service.pauseTranscription());
        async.elapse(const Duration(seconds: 20));
        unawaited(h.service.resumeTranscription());
        async.elapse(Duration.zero);
      } else {
        for (int id = 100; id < 300; id++) {
          say(id, voiced: false);
        }
      }
      for (int id = 300; id < 350; id++) {
        say(id);
      }
      // Fenêtre 30–35 s perdue par la source distante (tampon de coupure
      // plein, par exemple) : le direct écrit son repère.
      h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.input,
          startMs: h.t0 + 30000,
          endMs: h.t0 + 35000,
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      h.stop();
      async.elapse(const Duration(seconds: 5));
      segments = h.segments;
      sessionId = h.session.id;
      captureLog = List<String>.of(h.audio.log);
    });
  });
  final bool markerStored = segments
      .of(AudioSource.input)
      .any(
        (TranscriptSegmentEntity s) =>
            s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      );
  final String wav =
      '${LiveTranscriptionService.recordingsDir}/${sessionId}_mic.wav';
  final Duration? wavDuration = await disk.run(
    () => WavRecorder.recordedDuration(wav),
  );
  // Une erreur du rattrapage est prise comme dans l'app (le repère reste,
  // journal) et dite dans le message d'échec.
  Object? backfillError;
  try {
    await disk.run(
      () =>
          GapBackfillService(
            transcriber: _Listener(),
            transcripts: segments,
            isRecording: () => false,
          ).backfill(
            sessionId,
            recordingsDirectory: LiveTranscriptionService.recordingsDir,
          ),
    );
  } catch (e) {
    backfillError = e;
  }
  return (
    backfillError: backfillError,
    note: <String>[
      for (final TranscriptSegmentEntity s in segments.of(AudioSource.input))
        if (!s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
          s.text,
    ],
    markerStored: markerStored,
    wavDuration: wavDuration,
    captureLog: captureLog,
  );
}

void _expectSpeechAt30Recovered(_Run r) {
  expect(r.markerStored, isTrue, reason: 'le direct a écrit le repère');
  final String note = r.note.join(' ');
  final String why =
      'note « $note » ; durée du WAV ${r.wavDuration} pour 35 s de réunion'
      '${r.backfillError == null ? '' : ' ; rattrapage : ${r.backfillError}'}';
  expect('Dit à 30 s.'.allMatches(note).length, 1, reason: why);
  for (int s = 0; s < 10; s++) {
    expect(
      note,
      isNot(contains('Dit à $s s.')),
      reason: 'audio d avant la pause pris pour celui de 30 s ; $why',
    );
  }
}

/// Position (ms dans le WAV) du début du chunk parlé numéro [id], ou null.
int? _chunkAtMs(Uint8List wav, int id) {
  final ByteData d = ByteData.sublistView(wav);
  for (int p = 44; p + 8 <= wav.length; p += 2) {
    if (d.getInt16(p, Endian.little) == (id & 0x7FFF) &&
        d.getInt16(p + 2, Endian.little) == id >> 15 &&
        d.getInt16(p + 4, Endian.little) == 1200) {
      return (p - 44) ~/ 32;
    }
  }
  return null;
}

typedef _Cycles = ({
  int wallMs,
  int afterSecondResumeMs,
  Map<String, Duration?> durations,
  Map<String, int?> positions,
});

/// Revue de la PR #34 : la vraie capture rend son premier chunk ~0,5 s
/// après `startCapture`. Réunion micro + système, chaque chunk numéroté par
/// son heure murale (× 100 ms) : 5 s de parole, pause 10 s, reprise, 5 s,
/// pause 10 s, reprise, 5 s, arrêt.
_Cycles _twoPauseCycles() {
  final _Disk disk = _Disk();
  late _Cycles out;
  disk.run(() {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(
        async,
        createWavRecorder: WavRecorder.new,
      );
      h.audio.startDelay = const Duration(milliseconds: 500);
      unawaited(
        h.service.startTranscription(
          outputEnabled: true,
          serverCommand: LiveServiceHarness.command,
          serverArgs: LiveServiceHarness.args,
        ),
      );
      async.elapse(const Duration(milliseconds: 500));
      // Heure murale depuis l'ouverture de la session (horloge factice ;
      // `createdAt` vient de DateTime.now, d'où t0 pour les horodatages).
      final int t0 = h.t0;
      final Duration opened = async.elapsed;
      int wall() => (async.elapsed - opened).inMilliseconds;
      void speak(int ms) {
        for (int i = 0; i < ms ~/ 100; i++) {
          final int id = wall() ~/ 100;
          for (final AudioSource source in AudioSource.values) {
            h.audio.emit(chunk(source, id, timestampMs: t0 + id * 100));
          }
          async.elapse(const Duration(milliseconds: 100));
        }
      }

      void pauseThenResume() {
        unawaited(h.service.pauseTranscription());
        async.elapse(const Duration(seconds: 10));
        unawaited(h.service.resumeTranscription());
        // Premier chunk de la capture relancée : 0,5 s après l'appel.
        async.elapse(const Duration(milliseconds: 500));
      }

      speak(5000);
      pauseThenResume();
      speak(5000);
      pauseThenResume();
      final int afterSecondResumeMs = wall();
      speak(5000);
      final int wallMs = wall();
      unawaited(h.service.stopTranscription());
      async.elapse(const Duration(seconds: 10));
      final String dir = LiveTranscriptionService.recordingsDir;
      final Map<String, Duration?> durations = <String, Duration?>{};
      final Map<String, int?> positions = <String, int?>{};
      for (final String track in <String>['mic', 'system']) {
        final String path = '$dir/${h.session.id}_$track.wav';
        WavRecorder.recordedDuration(path).then((Duration? d) {
          durations[track] = d;
        });
        async.flushMicrotasks();
        final Uint8List? bytes = disk.bytes[path];
        positions[track] = bytes == null
            ? null
            : _chunkAtMs(bytes, afterSecondResumeMs ~/ 100);
      }
      out = (
        wallMs: wallMs,
        afterSecondResumeMs: afterSecondResumeMs,
        durations: durations,
        positions: positions,
      );
    });
  });
  return out;
}

void main() {
  test('deux pauses, capture qui reprend en 0,5 s : chaque WAV dure le temps '
      'mural de la réunion, et la parole d après la 2e reprise est à son heure '
      'murale dans le WAV', () {
    final _Cycles r = _twoPauseCycles();
    final String why =
        'réunion ${r.wallMs} ms ; WAV ${r.durations} ; parole dite à '
        '${r.afterSecondResumeMs} ms trouvée à ${r.positions} ms';
    for (final String track in <String>['mic', 'system']) {
      final Duration? d = r.durations[track];
      expect(d, isNotNull, reason: '$track : $why');
      expect(
        (d!.inMilliseconds - r.wallMs).abs(),
        lessThanOrEqualTo(100),
        reason: 'durée du WAV $track ; $why',
      );
      final int? at = r.positions[track];
      expect(at, isNotNull, reason: '$track : $why');
      expect(
        (at! - r.afterSecondResumeMs).abs(),
        lessThanOrEqualTo(100),
        reason: 'place de la parole dans le WAV $track ; $why',
      );
    }
  });

  test('témoin sans pause : la parole perdue à 30 s revient du WAV au '
      'rattrapage', () async {
    _expectSpeechAt30Recovered(await _meeting(pause: false));
  });

  test('après une pause de 20 s, la parole perdue à 30 s revient du WAV au '
      'rattrapage (l audio lu est celui capté à 30 s)', () async {
    final _Run r = await _meeting(pause: true);
    expect(r.captureLog, <String>[
      'capture.start(output: false)',
      'capture.stop',
      'capture.start(output: false)',
      'capture.stop',
    ], reason: 'la pause a coupé la capture, la reprise l a relancée');
    _expectSpeechAt30Recovered(r);
  });
}
