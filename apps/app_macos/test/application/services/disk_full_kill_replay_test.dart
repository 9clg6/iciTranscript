import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/launch_repair.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Revue de la PR #31, point 1 : un trou du WAV ne doit JAMAIS se lire comme
// du silence après un arrêt brutal. Depuis #28, une tranche rattrapée sans
// parole compte comme rendue et son repère de perte part ; la seule chose
// qui distingue « pas de copie audio » d'un silence est le repère « Pas de
// copie audio », écrit pendant que le disque est plein… donc peut-être
// seulement en mémoire.
//
// Rejeu au niveau du service : vrai `LiveTranscriptionService`, vraie
// source distante sur sockets factices, VRAI `WavRecorder` sur un disque en
// mémoire qui se remplit comme un vrai (écriture partielle, puis ENOSPC),
// base qui refuse d'écrire tant que le disque est plein ; arrêt brutal
// (plus rien ne tourne) ; relancement avec de la place : la base et le WAV
// tels que laissés, rattrapage avec un transcripteur sain qui ne rend que
// ce qui est parlé dans l'audio lu (rien pour des zéros).
//
// Décision (coordinateur) : une fois le disque à zéro, rien ne peut
// s'écrire ; ce qui manque est donc écrit au RELANCEMENT, par la
// réparation qui passe la session restée active à `interrupted` : pour
// chaque source enregistrée, un repère OUVERT à son dernier point durable
// (le plus tardif entre son dernier segment rangé et la fin de son WAV),
// « Rien n'a pu être enregistré après hh:mm:ss (app arrêtée ou disque
// plein) » — une sorte de repère à part (même prédicat partagé
// `isTranscriptMarker`), jamais retirée par le rattrapage, jamais prise
// pour du silence. API : `LaunchRepair` (lib/application/services/
// launch_repair.dart) ; `LiveTranscriptionService
// .notRecordedAfterMarkerText(int startMs)` /
// `isNotRecordedAfterMarker(String)` ; `WavRecorder.recordedDuration(String
// path)` (longueur du fichier − 44 octets, à 32 o/ms ; null sans fichier) ;
// voir not_recorded_after_marker_test.dart.
//
// Attendu, après le relancement et le rattrapage : chaque phrase dite plus
// de 5 s avant l'arrêt est dans la note OU sous un repère (perte ou « pas
// de copie audio ») — jamais ni l'un ni l'autre ; un repère au-dessus d'un
// audio absent n'est pas retiré comme silence.
//
// Micro seul ; phrase k : k × 10 s à k × 10 + 7,5 s.

/// Disque en mémoire ; plein : la première écriture n'écrit qu'une partie
/// du tampon puis lève ENOSPC, les suivantes lèvent aussitôt.
final class _Disk {
  bool _full = false;
  bool _partialDone = false;
  final Map<String, Uint8List> bytes = <String, Uint8List>{};

  bool get full => _full;
  set full(bool v) {
    _full = v;
    _partialDone = false;
  }

  R run<R>(R Function() body) => IOOverrides.runZoned(
    body,
    createFile: (String path) => _File(this, path),
    createDirectory: (String path) => _Dir(path),
  );
}

FileSystemException _enospc(String path) => FileSystemException(
  'No space left on device',
  path,
  const OSError('No space left on device', 28),
);

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
    List<int> data = buffer.sublist(start, end);
    if (_disk.full) {
      if (_disk._partialDone) throw _enospc(_path);
      _disk._partialDone = true;
      data = data.sublist(0, data.length ~/ 3);
      _write(data);
      throw _enospc(_path);
    }
    _write(data);
    return this;
  }

  void _write(List<int> data) {
    Uint8List b = _disk.bytes[_path]!;
    if (_at + data.length > b.length) {
      b = Uint8List(_at + data.length)..setRange(0, b.length, b);
    }
    b.setRange(_at, _at + data.length, data);
    _disk.bytes[_path] = b;
    _at += data.length;
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
    final int end = (_at + count).clamp(0, b.length);
    final Uint8List out = Uint8List.fromList(b.sublist(_at, end));
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

/// Base qui refuse d'écrire tant que le disque est plein.
final class _Db extends InMemoryTranscriptRepository {
  _Db(this._disk);

  final _Disk _disk;

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) {
    if (_disk.full) {
      throw Exception('SqliteException(13): database or disk is full');
    }
    return super.save(segment);
  }
}

/// Transcripteur sain : la phrase k pour chaque chunk parlé de son début
/// dans l'audio lu (numéro du chunk dans ses deux premiers échantillons).
final class _Healthy implements PcmTranscriber {
  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final List<({int offsetMs, String text})> out =
        <({int offsetMs, String text})>[];
    for (int c = 0; (c + 1) * 3200 <= pcm.length; c++) {
      final Uint8List chunk = Uint8List.sublistView(
        pcm,
        c * 3200,
        (c + 1) * 3200,
      );
      if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(chunk)) continue;
      final ByteData d = ByteData.sublistView(chunk);
      final int id =
          d.getInt16(0, Endian.little) + (d.getInt16(2, Endian.little) << 15);
      if (id % 100 == 0) {
        out.add((offsetMs: c * 100, text: 'Phrase lue ${id ~/ 100}.'));
      }
    }
    return out;
  }
}

typedef _Left = ({
  String session,
  List<TranscriptSegmentEntity> store,
  List<SessionEntity> sessions,
  int killMs,
});

/// Joue une réunion micro jusqu'à [killId] (× 100 ms) ; coupure réseau de
/// [outageFrom] à la fin si donnée ; disque plein de [fullFrom] à
/// [fullTo] (null : jusqu'à l'arrêt brutal). Rend ce qui reste au
/// relancement ; le disque [disk] garde le WAV.
_Left _play(
  _Disk disk, {
  required int killId,
  required int fullFrom,
  int? fullTo,
  int? outageFrom,
}) {
  late _Left left;
  disk.run(() {
    fakeAsync((FakeAsync async) {
      final FakeVoxServer server = FakeVoxServer();
      final FakeVoxSocket mic = FakeVoxSocket(server);
      final _Db db = _Db(disk);
      final LiveServiceHarness h = LiveServiceHarness(
        async,
        remote: TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        ),
        segments: db,
        createWavRecorder: WavRecorder.new,
      )..start(outputEnabled: false);
      for (int id = 0; id < killId; id++) {
        if (id == outageFrom) {
          mic
            ..refusing = true
            ..drop();
        }
        if (id == fullFrom) disk.full = true;
        if (id == fullTo) disk.full = false;
        h.audio.emit(
          chunk(
            AudioSource.input,
            id,
            timestampMs: h.t0 + id * 100,
            voiced: id % 100 < 75,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));
      }
      // Arrêt brutal : plus rien ne tourne ; la base reste telle quelle.
      left = (
        session: h.session.id,
        store: db.store.values
            .where((TranscriptSegmentEntity s) => s.sessionId == h.session.id)
            .toList(),
        sessions: h.sessions.store.values.toList(),
        killMs: killId * 100,
      );
    });
  });
  return left;
}

bool _isMarker(TranscriptSegmentEntity s) => isTranscriptMarker(s.text);

({int startMs, int endMs})? _range(String text) {
  final List<int> t = <int>[
    for (final RegExpMatch m in RegExp(
      r'(\d+):(\d{2}):(\d{2})',
    ).allMatches(text))
      ((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 60 +
              int.parse(m.group(3)!)) *
          1000,
  ];
  // Repère ouvert « Rien n'a pu être enregistré après … » : une seule
  // heure, il couvre tout ce qui suit sur sa source.
  if (LiveTranscriptionService.isNotRecordedAfterMarker(text) && t.isNotEmpty) {
    return (startMs: t.first, endMs: 1 << 40);
  }
  return t.length < 2 ? null : (startMs: t[0], endMs: t[1]);
}

/// Relance avec de la place, comme le lancement : la vraie réparation des
/// sessions restées actives ([LaunchRepair] : session `interrupted`, repère
/// ouvert par source à son dernier point durable, fin du WAV lue par
/// `WavRecorder.recordedDuration`), puis le rattrapage sur la base et le WAV
/// laissés ; rend les phrases ni dans la note ni sous un repère.
Future<List<String>> _relaunch(_Disk disk, _Left left) async {
  disk.full = false;
  final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
  for (final TranscriptSegmentEntity s in left.store) {
    await repo.save(s);
  }
  final InMemorySessionRepository sessions = InMemorySessionRepository();
  for (final SessionEntity s in left.sessions) {
    sessions.store[s.id] = s;
  }
  await disk.run(
    () => LaunchRepair(
      sessions: sessions,
      transcripts: repo,
      recordingsDir: LiveTranscriptionService.recordingsDir,
    ).run(),
  );
  expect(
    sessions.store[left.session]!.status,
    SessionStatus.interrupted,
    reason: 'la réparation du lancement a tourné',
  );
  await disk.run(
    () =>
        GapBackfillService(
          transcriber: _Healthy(),
          transcripts: repo,
          isRecording: () => false,
        ).backfill(
          left.session,
          recordingsDirectory: LiveTranscriptionService.recordingsDir,
        ),
  );
  final List<TranscriptSegmentEntity> lines = repo.of(AudioSource.input);
  final List<String> neither = <String>[];
  for (int k = 0; k * 10000 + 7500 <= left.killMs - 5000; k++) {
    final int start = k * 10000;
    final bool said = lines.any(
      (TranscriptSegmentEntity l) =>
          !_isMarker(l) &&
          (l.text.contains('Phrase lue $k.') ||
              (l.text.startsWith('Phrase numéro') &&
                  l.timestampMs >= start - 500 &&
                  l.timestampMs <= start + 7500)),
    );
    final bool covered = lines.any((TranscriptSegmentEntity m) {
      final ({int startMs, int endMs})? r = _isMarker(m)
          ? _range(m.text)
          : null;
      return r != null &&
          r.startMs <= start + 1000 &&
          r.endMs + 1000 >= start + 7500;
    });
    // Un repère ouvert retiré par le rattrapage serait du silence supposé.
    if (said || covered) continue;
    if (!said && !covered) neither.add('phrase $k (${start ~/ 1000} s)');
  }
  return neither;
}

void main() {
  test('coupure réseau, puis disque plein pendant la coupure, arrêt brutal, '
      'relancement : l audio absent reste sous un repère, aucune phrase '
      'perdue en silence', () async {
    final _Disk disk = _Disk();
    final _Left left = _play(
      disk,
      killId: 1500,
      outageFrom: 600,
      fullFrom: 900,
    );
    expect(
      left.store.where(
        (TranscriptSegmentEntity s) =>
            s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
      ),
      isNotEmpty,
      reason: 'le repère de la coupure était rangé avant le disque plein',
    );
    final List<String> neither = await _relaunch(disk, left);
    expect(neither, isEmpty, reason: neither.join(', '));
  });

  test('sans coupure : disque plein 2 min en pleine réunion, arrêt brutal '
      'PENDANT le disque plein, relancement : aucune phrase perdue en '
      'silence', () async {
    final _Disk disk = _Disk();
    final _Left left = _play(disk, killId: 1500, fullFrom: 600);
    final List<String> neither = await _relaunch(disk, left);
    expect(neither, isEmpty, reason: neither.join(', '));
  });

  test('sans coupure : disque plein 2 min en pleine réunion, la place '
      'revient, arrêt brutal juste après, relancement : le trou n est pas lu '
      'comme du silence, aucune phrase perdue en silence', () async {
    final _Disk disk = _Disk();
    final _Left left = _play(disk, killId: 1850, fullFrom: 600, fullTo: 1800);
    final List<String> neither = await _relaunch(disk, left);
    expect(neither, isEmpty, reason: neither.join(', '));
  });
}
