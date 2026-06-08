import 'dart:io';
import 'dart:typed_data';

/// Enregistre un flux PCM 16 bits mono dans un fichier WAV en streaming.
///
/// L'en-tête est écrit avec des tailles à zéro à l'ouverture, le PCM est
/// ajouté au fil de l'eau, puis les tailles sont corrigées à la fermeture.
/// Évite de garder tout l'audio en mémoire (réunions longues).
class WavRecorder {
  WavRecorder({this.sampleRate = 16000});

  /// Fréquence d'échantillonnage (Hz).
  final int sampleRate;

  RandomAccessFile? _raf;
  int _dataBytes = 0;

  bool get isOpen => _raf != null;

  /// Ouvre [path] et écrit un en-tête WAV provisoire (tailles = 0).
  Future<void> open(String path) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    _raf = await file.open(mode: FileMode.write);
    _dataBytes = 0;
    await _raf!.writeFrom(_header(0));
  }

  /// Ajoute un bloc PCM int16 little-endian.
  Future<void> append(Uint8List pcm) async {
    final RandomAccessFile? raf = _raf;
    if (raf == null) return;
    await raf.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  /// Corrige l'en-tête (tailles réelles) et ferme le fichier.
  Future<void> close() async {
    final RandomAccessFile? raf = _raf;
    if (raf == null) return;
    await raf.setPosition(0);
    await raf.writeFrom(_header(_dataBytes));
    await raf.close();
    _raf = null;
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
