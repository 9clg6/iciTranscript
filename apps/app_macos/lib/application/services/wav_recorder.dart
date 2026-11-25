import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Enregistre un flux PCM 16 bits mono dans un fichier WAV en streaming.
///
/// L'en-tête est écrit avec des tailles à zéro à l'ouverture, le PCM est
/// ajouté au fil de l'eau et les tailles suivent chaque seconde d'audio, puis
/// sont corrigées à la fermeture. Après un crash, le fichier reste lisible
/// (au plus 1 s hors en-tête) et [repair] le recale sur sa taille.
/// Évite de garder tout l'audio en mémoire (réunions longues).
class WavRecorder {
  WavRecorder({this.sampleRate = 16000});

  /// Fréquence d'échantillonnage (Hz).
  final int sampleRate;

  RandomAccessFile? _raf;
  int _dataBytes = 0;
  int _headerDataBytes = 0;
  Future<void> _pendingWrites = Future<void>.value();
  bool _acceptingWrites = false;

  // Disque plein : chaque chunk garde sa place dans le temps (le rattrapage
  // lit par l'heure) ; l'écriture est retentée à chaque chunk, et
  // l'intervalle sans copie est rendu par [missing].
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  int? _failedAtBytes;
  bool _seek = false;
  final List<({int startMs, int endMs})> _missing =
      <({int startMs, int endMs})>[];

  bool get isOpen => _raf != null;

  /// Une erreur à chaque début d'échec d'écriture (disque plein…), tout de
  /// suite, pas à la fermeture.
  Stream<Object> get writeErrors => _errors.stream;

  /// L'écriture échoue en ce moment.
  bool get failing => _failedAtBytes != null;

  /// Intervalles (ms depuis le début du WAV) dont l'audio n'a pas été
  /// écrit : ni rattrapables ni du silence vérifié.
  List<({int startMs, int endMs})> get missing =>
      List<({int startMs, int endMs})>.unmodifiable(_missing);

  /// Ouvre [path] et écrit un en-tête WAV provisoire (tailles = 0).
  Future<void> open(String path) async {
    if (_raf != null) {
      throw StateError('WavRecorder is already open');
    }

    final File file = File(path);
    await file.parent.create(recursive: true);
    _raf = await file.open(mode: FileMode.write);
    _dataBytes = 0;
    _headerDataBytes = 0;
    _pendingWrites = Future<void>.value();
    _failedAtBytes = null;
    _seek = false;
    _missing.clear();
    await _raf!.writeFrom(_header(0));
    _acceptingWrites = true;
  }

  /// Ajoute un bloc PCM int16 little-endian.
  ///
  /// Les appels peuvent être lancés sans `await` : chaque écriture est chaînée
  /// après la précédente ; un échec est signalé par [writeErrors].
  Future<void> append(Uint8List pcm) {
    final RandomAccessFile? raf = _raf;
    if (raf == null || !_acceptingWrites || pcm.isEmpty) {
      return Future<void>.value();
    }

    // The platform chunk is owned by the caller. Keep an immutable snapshot
    // until its turn in the write chain.
    final Uint8List pendingPcm = Uint8List.fromList(pcm);
    _pendingWrites = _pendingWrites.then((_) async {
      final int at = _dataBytes;
      // Sa place est gardée, écrit ou non.
      _dataBytes += pendingPcm.length;
      try {
        if (_seek) await raf.setPosition(_headerBytes + at);
        _seek = false;
        await raf.writeFrom(pendingPcm);
        final int? failedAt = _failedAtBytes;
        if (failedAt != null) {
          _missing.add((startMs: _ms(failedAt), endMs: _ms(at)));
          _failedAtBytes = null;
        }
        if (_dataBytes - _headerDataBytes >= _bytesPerSecond) {
          await raf.setPosition(0);
          await raf.writeFrom(_header(_dataBytes));
          await raf.setPosition(_headerBytes + _dataBytes);
          _headerDataBytes = _dataBytes;
        }
      } catch (error) {
        _seek = true;
        if (_failedAtBytes == null) {
          _failedAtBytes = at;
          _errors.add(error);
        }
      }
    });
    return _pendingWrites;
  }

  /// Corrige l'en-tête (tailles réelles) et ferme le fichier.
  Future<void> close() async {
    final RandomAccessFile? raf = _raf;
    if (raf == null) return;

    // Prevent a new append from extending the chain after the await below.
    _acceptingWrites = false;
    await _pendingWrites;

    final int? failedAt = _failedAtBytes;
    if (failedAt != null) {
      _missing.add((startMs: _ms(failedAt), endMs: _ms(_dataBytes)));
      _failedAtBytes = null;
    }
    Object? closeError;
    StackTrace? closeErrorStackTrace;
    try {
      await raf.setPosition(0);
      await raf.writeFrom(_header(_dataBytes));
    } catch (error, stackTrace) {
      closeError ??= error;
      closeErrorStackTrace ??= stackTrace;
    }

    try {
      await raf.close();
    } catch (error, stackTrace) {
      closeError ??= error;
      closeErrorStackTrace ??= stackTrace;
    } finally {
      _raf = null;
      _pendingWrites = Future<void>.value();
    }

    if (closeError != null) {
      Error.throwWithStackTrace(
        closeError,
        closeErrorStackTrace ?? StackTrace.current,
      );
    }
  }

  static const int _headerBytes = 44;

  int get _bytesPerSecond => sampleRate * 2;

  int _ms(int bytes) => bytes * 1000 ~/ _bytesPerSecond;

  /// Durée d'audio de [path] d'après sa taille (en-tête de 44 octets,
  /// 32 octets par ms à 16 kHz) ; null sans fichier.
  static Future<Duration?> recordedDuration(String path) async {
    final File file = File(path);
    if (!file.existsSync()) return null;
    final int bytes = await file.length() - _headerBytes;
    return Duration(milliseconds: bytes <= 0 ? 0 : bytes ~/ 32);
  }

  /// Recale les tailles d'un WAV dont l'en-tête n'a pas été finalisé (app
  /// arrêtée en pleine session) sur la taille réelle du fichier.
  ///
  /// Sans effet sur un WAV déjà juste, un fichier trop court ou qui n'est
  /// pas un WAV écrit par cette classe. Un demi-échantillon final est ignoré.
  static Future<void> repair(String path) async {
    final RandomAccessFile raf = await File(path).open(mode: FileMode.append);
    try {
      final int length = await raf.length();
      if (length < _headerBytes) return;
      await raf.setPosition(0);
      final Uint8List head = await raf.read(_headerBytes);
      final ByteData h = ByteData.sublistView(head);
      if (String.fromCharCodes(head, 0, 4) != 'RIFF' ||
          String.fromCharCodes(head, 8, 12) != 'WAVE' ||
          String.fromCharCodes(head, 36, 40) != 'data') {
        return;
      }
      final int dataBytes = (length - _headerBytes) & ~1;
      if (h.getUint32(40, Endian.little) == dataBytes &&
          h.getUint32(4, Endian.little) == 36 + dataBytes) {
        return;
      }
      h.setUint32(4, 36 + dataBytes, Endian.little);
      h.setUint32(40, dataBytes, Endian.little);
      await raf.setPosition(0);
      await raf.writeFrom(head);
    } finally {
      await raf.close();
    }
  }

  /// Construit un en-tête WAV canonical (44 octets) PCM 16 bits mono.
  Uint8List _header(int dataBytes) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const int blockAlign = channels * bitsPerSample ~/ 8;
    final int chunkSize = 36 + dataBytes;

    final ByteData h = ByteData(44);
    void str(int off, String s) {
      for (int i = 0; i < s.length; i++) {
        h.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, chunkSize, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    h.setUint16(20, 1, Endian.little); // audio format = PCM
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, byteRate, Endian.little);
    h.setUint16(32, blockAlign, Endian.little);
    h.setUint16(34, bitsPerSample, Endian.little);
    str(36, 'data');
    h.setUint32(40, dataBytes, Endian.little);
    return h.buffer.asUint8List();
  }
}
