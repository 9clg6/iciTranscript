/// Corrige uniquement les artefacts de texte suffisamment caractéristiques
/// pour être traités sans réécrire le sens de la transcription.
abstract final class TranscriptTextNormalizer {
  static final RegExp _dottedWordRun = RegExp(
    r'(?:[A-Za-zÀ-ÖØ-öø-ÿŒœ]+\.){3,}[A-Za-zÀ-ÖØ-öø-ÿŒœ]+',
    unicode: true,
  );

  /// Remplace les longues suites `des.mots.écrits.comme.ça` par des espaces.
  ///
  /// Trois séparateurs consécutifs sont exigés pour préserver les domaines,
  /// versions, initiales et abréviations légitimes.
  static String normalize(String rawText) {
    final String withoutDottedRuns = rawText.replaceAllMapped(
      _dottedWordRun,
      (Match match) => match.group(0)!.replaceAll('.', ' '),
    );
    return withoutDottedRuns.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}
