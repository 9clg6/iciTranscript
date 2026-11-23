import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Fichiers en mémoire pour [IOOverrides] : les opérations de fichier du
/// rattrapage (WAV, fichier d'attente) se terminent en micro-tâches, donc
/// sous `fakeAsync` (des minutes de reprises en quelques millisecondes).
/// Seules les opérations utilisées par `GapBackfillService` et
/// `GapBackfillRetry` sont fournies ; toute autre lève.
final class MemoryFs {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// Exécute [body] avec `File` et `Directory` servis par cette mémoire.
  R run<R>(R Function() body) => IOOverrides.runZoned(
    body,
    createFile: (String path) => _MemFile(this, path),
    createDirectory: (String path) => _MemDir(path),
  );

  /// WAV PCM16 16 kHz mono : en-tête de 44 octets (non lu) puis [pcm].
  void wav(String path, Uint8List pcm) {
    files[path] = Uint8List(44 + pcm.length)
      ..setRange(44, 44 + pcm.length, pcm);
  }
}

final class _MemFile implements File {
  _MemFile(this._fs, this.path);

  final MemoryFs _fs;

  @override
  final String path;

  @override
  bool existsSync() => _fs.files.containsKey(path);

  @override
  Future<bool> exists() async => existsSync();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _MemRaf(_fs.files[path]!);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(_fs.files[path]!);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    _fs.files[path] = Uint8List.fromList(encoding.encode(contents));
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    _fs.files[newPath] = _fs.files.remove(path)!;
    return _MemFile(_fs, newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    _fs.files.remove(path);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MemoryFs : ${invocation.memberName}');
}

final class _MemRaf implements RandomAccessFile {
  _MemRaf(this._bytes);

  final Uint8List _bytes;
  int _at = 0;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    _at = position;
    return this;
  }

  @override
  Future<Uint8List> read(int count) async {
    final int end = (_at + count).clamp(0, _bytes.length);
    final Uint8List out = Uint8List.fromList(_bytes.sublist(_at, end));
    _at = end;
    return out;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MemoryFs : ${invocation.memberName}');
}

final class _MemDir implements Directory {
  _MemDir(this.path);

  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MemoryFs : ${invocation.memberName}');
}
