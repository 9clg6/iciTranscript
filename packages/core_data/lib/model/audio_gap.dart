import 'package:core_domain/domain/enum/audio_source.enum.dart';

/// Audio d'une source jamais transcrit : tampon de coupure plein (le plus
/// ancien est jeté) ou session close avant la reconnexion.
///
/// Horodatages de capture (ms epoch), intervalle `[startMs, endMs[`.
class AudioGap {
  /// Cree une instance de [AudioGap].
  const AudioGap({
    required this.source,
    required this.startMs,
    required this.endMs,
  });

  /// Source dont l'audio est perdu.
  final AudioSource source;

  /// Horodatage du premier chunk perdu.
  final int startMs;

  /// Fin du dernier chunk perdu (exclue).
  final int endMs;

  /// Durée d'audio perdue.
  Duration get duration => Duration(milliseconds: endMs - startMs);
}
