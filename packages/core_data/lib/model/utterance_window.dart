/// Intervalle de parole d'une source, en horodatage de capture (ms epoch).
///
/// Délimité par le premier et le dernier chunk audio voisés envoyés au
/// serveur de transcription pour une phrase : permet de retrouver, dans un
/// autre flux synchronisé sur les mêmes horodatages (ex. diarization), ce
/// qui se passait pendant cette phrase.
class UtteranceWindow {
  /// Cree une instance de [UtteranceWindow].
  const UtteranceWindow({required this.startMs, required this.endMs});

  /// Horodatage du premier chunk voisé.
  final int startMs;

  /// Horodatage du dernier chunk voisé.
  final int endMs;
}
