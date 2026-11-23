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
    this.episodeStartMs,
    this.episodeEndMs,
  });

  /// Source dont l'audio est perdu.
  final AudioSource source;

  /// Horodatage du premier chunk perdu.
  final int startMs;

  /// Fin du dernier chunk perdu (exclue).
  final int endMs;

  /// Début de la perte qui dure (borne qui déborde sur une socket vivante,
  /// sonde 9) dont ce morceau fait partie : l'app n'en montre qu'un repère,
  /// de ce début à la fin du dernier morceau. Null hors d'une telle perte.
  final int? episodeStartMs;

  /// Fin connue de cette perte qui dure. Un morceau vide ([startMs] ==
  /// [endMs], au début de la perte) ne fait que prolonger le repère jusque-là
  /// (audio déjà parti, jeté de la borne).
  final int? episodeEndMs;

  /// Durée d'audio perdue.
  Duration get duration => Duration(milliseconds: endMs - startMs);
}
