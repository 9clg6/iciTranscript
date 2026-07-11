import 'dart:typed_data';

import 'package:core_domain/domain/enum/audio_source.enum.dart';

/// Chunk audio brut partage entre la couche plateforme et la couche data.
///
/// Represente un fragment audio avec sa source et son timestamp.
class AudioChunk {
  /// Cree une instance de [AudioChunk].
  const AudioChunk({
    required this.source,
    required this.data,
    required this.timestampMs,
  });

  /// Source audio (micro input ou systeme output).
  final AudioSource source;

  /// Donnees audio brutes (PCM Int16 little-endian, 16 kHz mono).
  final Uint8List data;

  /// Timestamp en millisecondes depuis le debut de la session.
  final int timestampMs;
}
