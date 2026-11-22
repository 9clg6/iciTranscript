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

  // Formules que le modèle invente sur du silence ou de la musique, sous
  // forme de clé (voir [_key]).
  static final Set<String> _knownHallucinations = <String>{
    'thank you',
    'thanks for watching',
    "sous titres réalisés par la communauté d'amara org",
    "merci d'avoir regardé cette vidéo",
    '♪',
    'you',
    'okay',
  };

  /// Texte final à garder, boucles de répétition réduites, ou null pour
  /// l'écarter.
  ///
  /// Une formule connue (« Thank you. », « ♪ »…) n'est écartée que si
  /// l'audio n'avait pas de parole ([hadSpeechEnergy] faux) ou si elle suit
  /// déjà deux fois de suite dans [previousTexts] (textes finalisés juste
  /// avant pour la même source, du plus ancien au plus récent). Une réponse
  /// courte dite avec de la parole est gardée.
  static String? filterFinalText(
    String text, {
    required bool hadSpeechEnergy,
    required List<String> previousTexts,
  }) {
    final String reduced = _reduceLoops(text);
    if (reduced.isEmpty) return null;
    final String key = _key(reduced);
    if (!_knownHallucinations.contains(key)) return reduced;
    if (!hadSpeechEnergy) return null;
    final bool thirdInARow =
        previousTexts.length >= 2 &&
        previousTexts
            .sublist(previousTexts.length - 2)
            .every((String previous) => _key(_reduceLoops(previous)) == key);
    return thirdInARow ? null : reduced;
  }

  /// Casse, ponctuation et espaces ignorés ; une suite de « ♪ » vaut un.
  static String _key(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}♪']+", unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'♪( ♪)*'), '♪');

  /// Réduit à une occurrence toute suite de mots répétée au moins trois
  /// fois de suite (« okay okay okay » → « okay »). Deux fois reste naturel.
  static String _reduceLoops(String text) {
    final List<String> words = text.trim().split(RegExp(r'\s+'))
      ..removeWhere((String w) => w.isEmpty);
    final List<String> keys = words.map(_key).toList();
    final List<String> kept = <String>[];
    int i = 0;
    while (i < words.length) {
      int step = 1;
      for (int length = 1; i + 3 * length <= words.length; length++) {
        int repeats = 1;
        while (i + (repeats + 1) * length <= words.length &&
            _sameRun(keys, i, i + repeats * length, length)) {
          repeats++;
        }
        if (repeats >= 3) {
          step = repeats * length;
          kept.addAll(words.sublist(i, i + length));
          break;
        }
      }
      if (step == 1) kept.add(words[i]);
      i += step;
    }
    return kept.join(' ');
  }

  static bool _sameRun(List<String> keys, int a, int b, int length) {
    for (int k = 0; k < length; k++) {
      if (keys[a + k] != keys[b + k]) return false;
    }
    return true;
  }
}
