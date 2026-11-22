/// Intervalle de parole d'une source, en horodatage de capture (ms epoch).
///
/// Délimité par le premier et le dernier chunk audio voisés envoyés au
/// serveur de transcription pour une phrase : permet de retrouver, dans un
/// autre flux synchronisé sur les mêmes horodatages (ex. diarization), ce
/// qui se passait pendant cette phrase.
class UtteranceWindow {
  /// Cree une instance de [UtteranceWindow].
  const UtteranceWindow({
    required this.startMs,
    required this.endMs,
    this.hadSpeech = true,
  });

  /// Horodatage du premier chunk voisé.
  final int startMs;

  /// Horodatage du dernier chunk voisé.
  final int endMs;

  /// Faux si l'audio de la phrase est resté trop peu de temps au-dessus du
  /// seuil de parole : un texte « connu » (ex. « Thank you. ») y est alors
  /// une hallucination probable.
  final bool hadSpeech;
}
