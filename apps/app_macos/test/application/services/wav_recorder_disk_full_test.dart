import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

// Disque plein pendant une réunion (le Mac de l'utilisateur : 4,9 Go
// libres). Aujourd'hui `WavRecorder.append` garde la PREMIÈRE erreur
// d'écriture et jette en silence tout l'audio suivant ; l'erreur ne sort
// qu'à `close()`. Le WAV est le filet de tous les rattrapages : après le
// disque plein, plus aucune perte n'est rattrapable, sans que personne le
// sache.
//
// Attendu :
// - une écriture ratée se voit TOUT DE SUITE (`writeErrors`, `failing`),
//   jamais seulement à la fermeture ;
// - les écritures suivantes sont retentées : quand la place revient,
//   l'écriture reprend et `failing` repasse à faux ;
// - l'axe du temps du WAV reste juste : le chunk n s'écrit à
//   44 + n × 3200 octets (le rattrapage lit par l'heure) ; l'intervalle
//   sans copie est rendu (`missing`, en ms depuis le début du WAV) pour que
//   la note le dise ; il n'est JAMAIS présenté comme du silence vérifié.
//
// API supposée : `Stream<Object> get writeErrors`, `bool get failing`,
// `List<({int startMs, int endMs})> get missing` sur [WavRecorder].
//
// Banc : fichier en mémoire (IOOverrides) dont les écritures lèvent
// ENOSPC tant que [_Disk.full] est vrai ; jamais le vrai disque.
final class _Disk {
  bool full = false;
  final Map<String, BytesBuilder> files = <String, BytesBuilder>{};
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
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    _disk.bytes[path] = Uint8List(0);
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
    if (_disk.full) {
      throw FileSystemException(
        'No space left on device',
        _path,
        const OSError('No space left on device', 28),
      );
    }
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Chunk de 100 ms numéroté (premier échantillon = n + 1, jamais 0).
Uint8List _chunk(int n) {
  final Uint8List c = Uint8List(3200);
  ByteData.sublistView(c).setInt16(0, n + 1, Endian.little);
  return c;
}

int _at(Uint8List wav, int n) =>
    ByteData.sublistView(wav).getInt16(44 + n * 3200, Endian.little);

void main() {
  const String path = '/mem/rec/1700000000000_mic.wav';

  test('une écriture ratée (disque plein) se voit tout de suite, pas à la '
      'fermeture', () async {
    final _Disk disk = _Disk();
    await disk.run(() async {
      final WavRecorder w = WavRecorder();
      final List<Object> errors = <Object>[];
      w.writeErrors.listen(errors.add);
      await w.open(path);
      for (int n = 0; n < 10; n++) {
        await w.append(_chunk(n));
      }
      disk.full = true;
      await w.append(_chunk(10));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(w.failing, isTrue);
      disk.full = false;
      await w.close();
    });
  });

  test('la place revient : l écriture reprend, à sa vraie place dans le '
      'temps, et l intervalle sans copie est rendu', () async {
    final _Disk disk = _Disk();
    await disk.run(() async {
      final WavRecorder w = WavRecorder();
      await w.open(path);
      for (int n = 0; n < 50; n++) {
        await w.append(_chunk(n)); // 0–5 s écrits
      }
      disk.full = true;
      for (int n = 50; n < 80; n++) {
        await w.append(_chunk(n)); // 5–8 s : disque plein
      }
      disk.full = false;
      for (int n = 80; n < 120; n++) {
        await w.append(_chunk(n)); // 8–12 s : la place est revenue
      }
      expect(w.failing, isFalse, reason: 'l écriture a repris');
      await w.close();

      final Uint8List wav = disk.bytes[path]!;
      expect(wav.length, 44 + 120 * 3200, reason: 'axe du temps gardé');
      expect(_at(wav, 49), 50);
      expect(_at(wav, 80), 81, reason: 'chunk 80 à 8,0 s');
      expect(_at(wav, 119), 120);
      expect(w.missing, isNotEmpty);
      final ({int startMs, int endMs}) gap = w.missing.single;
      expect(gap.startMs, lessThanOrEqualTo(5000));
      expect(gap.endMs, greaterThanOrEqualTo(8000));
      expect(gap.endMs, lessThanOrEqualTo(8100), reason: 'rien de plus');
    });
  });

  test('l audio écrit avant le disque plein n est jamais perdu', () async {
    final _Disk disk = _Disk();
    await disk.run(() async {
      final WavRecorder w = WavRecorder();
      await w.open(path);
      for (int n = 0; n < 30; n++) {
        await w.append(_chunk(n));
      }
      disk.full = true;
      await w.append(_chunk(30));
      disk.full = false;
      await w.close().catchError((Object _) {});
      final Uint8List wav = disk.bytes[path]!;
      for (int n = 0; n < 30; n++) {
        expect(_at(wav, n), n + 1);
      }
    });
  });
}
