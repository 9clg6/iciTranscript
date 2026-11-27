/// Sort d'un mot dans le diff d'une correction.
enum CoachDiffKind {
  /// Présent dans les deux phrases.
  same,

  /// Seulement dans la phrase dite.
  removed,

  /// Seulement dans la meilleure tournure.
  added,
}

/// Un mot du diff, avec son sort.
class CoachDiffToken {
  /// Crée un jeton.
  const CoachDiffToken(this.text, this.kind);

  /// Le mot, sans espace.
  final String text;

  /// Son sort.
  final CoachDiffKind kind;
}

List<String> _words(String s) =>
    s.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();

/// Diff mot à mot minimal (plus longue suite commune) de [original] vers
/// [corrected], dans l'ordre de lecture.
List<CoachDiffToken> coachWordDiff(String original, String corrected) {
  final List<String> a = _words(original);
  final List<String> b = _words(corrected);
  // lcs[i][j] : longueur de la suite commune de a[i..] et b[j..].
  final List<List<int>> lcs = <List<int>>[
    for (int i = 0; i <= a.length; i++) List<int>.filled(b.length + 1, 0),
  ];
  for (int i = a.length - 1; i >= 0; i--) {
    for (int j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final List<CoachDiffToken> out = <CoachDiffToken>[];
  int i = 0;
  int j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      out.add(CoachDiffToken(a[i++], CoachDiffKind.same));
      j++;
    } else if (i < a.length &&
        (j == b.length || lcs[i + 1][j] >= lcs[i][j + 1])) {
      out.add(CoachDiffToken(a[i++], CoachDiffKind.removed));
    } else {
      out.add(CoachDiffToken(b[j++], CoachDiffKind.added));
    }
  }
  return out;
}
