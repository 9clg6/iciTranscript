import 'dart:io';

/// Place disque pour une note.
enum StorageLevel { ok, low, critical }

/// État de la place disque d'une note, et seul endroit de ses règles.
///
/// - « peu de place » : moins de [lowRecordingTime] d'enregistrement
///   possibles pour les sources réellement enregistrées
///   ([bytesPerSourceSecond] chacune) ;
/// - « critique » : moins de [criticalBytes] libres ;
/// - contrôle au départ, puis toutes les [checkEvery].
class RecordingStorage {
  /// Cree une instance de [RecordingStorage] (défaut : tout va bien).
  const RecordingStorage({
    this.level = StorageLevel.ok,
    this.recordingTimeLeft,
    this.audioCopyFailing = false,
    this.unsavedLines = 0,
  });

  static const Duration lowRecordingTime = Duration(hours: 2);
  static const int criticalBytes = 200 * 1000 * 1000;
  static const Duration checkEvery = Duration(seconds: 30);

  /// PCM16 mono 16 kHz.
  static const int bytesPerSourceSecond = 32000;

  final StorageLevel level;

  /// Temps d'enregistrement que la place libre permet encore (null : place
  /// inconnue).
  final Duration? recordingTimeLeft;

  /// Une écriture WAV échoue : le rattrapage ne couvrira pas ce passage.
  final bool audioCopyFailing;

  /// Phrases ou repères montrés mais pas encore rangés en base.
  final int unsavedLines;

  /// Place libre [freeBytes] pour [sources] sources enregistrées. Une place
  /// inconnue (null) ne prévient de rien.
  RecordingStorage withFreeBytes(int? freeBytes, int sources) {
    if (freeBytes == null || sources <= 0) {
      return copyWith(level: StorageLevel.ok, clearTimeLeft: true);
    }
    final Duration left = Duration(
      seconds: freeBytes ~/ (sources * bytesPerSourceSecond),
    );
    final StorageLevel level = freeBytes < criticalBytes
        ? StorageLevel.critical
        : left < lowRecordingTime
        ? StorageLevel.low
        : StorageLevel.ok;
    return copyWith(level: level, recordingTimeLeft: left);
  }

  RecordingStorage copyWith({
    StorageLevel? level,
    Duration? recordingTimeLeft,
    bool clearTimeLeft = false,
    bool? audioCopyFailing,
    int? unsavedLines,
  }) => RecordingStorage(
    level: level ?? this.level,
    recordingTimeLeft: clearTimeLeft
        ? null
        : recordingTimeLeft ?? this.recordingTimeLeft,
    audioCopyFailing: audioCopyFailing ?? this.audioCopyFailing,
    unsavedLines: unsavedLines ?? this.unsavedLines,
  );

  /// Rien à signaler.
  bool get isFine =>
      level == StorageLevel.ok && !audioCopyFailing && unsavedLines == 0;

  @override
  bool operator ==(Object other) =>
      other is RecordingStorage &&
      other.level == level &&
      other.recordingTimeLeft == recordingTimeLeft &&
      other.audioCopyFailing == audioCopyFailing &&
      other.unsavedLines == unsavedLines;

  @override
  int get hashCode =>
      Object.hash(level, recordingTimeLeft, audioCopyFailing, unsavedLines);

  /// Place libre (octets) du volume qui contient [path], lue par `df -k` ;
  /// null si elle ne peut pas être lue.
  // ponytail: un processus `df` toutes les 30 s ; un appel natif
  // (volumeAvailableCapacityForImportantUsageKey) si cela pèse.
  static Future<int?> freeBytesAt(String path) async {
    try {
      final ProcessResult r = await Process.run('/bin/df', <String>[
        '-k',
        path,
      ]);
      if (r.exitCode != 0) return null;
      final List<String> lines = (r.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final List<String> cols = lines.last.trim().split(RegExp(r'\s+'));
      final int? kb = cols.length > 3 ? int.tryParse(cols[3]) : null;
      return kb == null ? null : kb * 1024;
    } on Exception {
      return null;
    }
  }
}
