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

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _latinLetter = RegExp(
    r'[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]',
  );

  /// Vrai si le texte est surtout écrit dans un autre alphabet que le latin
  /// (cyrillique, CJK…). Sur du bruit ou de la musique, le modèle invente
  /// parfois des mots dans une autre langue ; l'app transcrit du français et
  /// de l'anglais, on les écarte.
  static bool isForeignScript(String text) {
    final int letters = _letter.allMatches(text).length;
    if (letters == 0) return false;
    final int latin = _latinLetter.allMatches(text).length;
    return latin * 2 < letters;
  }
}
