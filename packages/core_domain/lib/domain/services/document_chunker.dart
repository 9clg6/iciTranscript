/// Taille maximale d'un morceau, en caracteres.
const int _maxChunkChars = 1200;

/// Decoupe un document texte / markdown en morceaux d'au plus
/// [_maxChunkChars] caracteres, pour la recherche plein texte.
///
/// Les paragraphes (separes par une ligne vide) sont regroupes tant que le
/// morceau tient dans la taille ; un paragraphe trop long est coupe entre
/// deux mots, et un mot trop long (URL, base64) est coupe a la limite.
/// Aucun morceau n'est vide ; tout le texte est couvert, dans l'ordre.
List<String> chunkDocument(String text) {
  final List<String> units = <String>[
    for (final String paragraph in text.split(RegExp(r'\n\s*\n')))
      if (paragraph.trim().isNotEmpty) ..._fit(paragraph.trim()),
  ];

  final List<String> chunks = <String>[];
  String current = '';
  for (final String unit in units) {
    if (current.isEmpty) {
      current = unit;
    } else if (current.length + 2 + unit.length <= _maxChunkChars) {
      current = '$current\n\n$unit';
    } else {
      chunks.add(current);
      current = unit;
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Coupe un paragraphe trop long en morceaux d'au plus [_maxChunkChars]
/// caracteres, entre deux mots.
// ponytail: les retours a la ligne simples d'un paragraphe trop long
// deviennent des espaces ; suffisant pour la recherche.
List<String> _fit(String paragraph) {
  if (paragraph.length <= _maxChunkChars) return <String>[paragraph];

  final List<String> pieces = <String>[];
  String current = '';
  for (final String word in paragraph.split(RegExp(r'\s+'))) {
    for (final String part in _splitWord(word)) {
      if (current.isEmpty) {
        current = part;
      } else if (current.length + 1 + part.length <= _maxChunkChars) {
        current = '$current $part';
      } else {
        pieces.add(current);
        current = part;
      }
    }
  }
  if (current.isNotEmpty) pieces.add(current);
  return pieces;
}

/// Coupe un mot plus long que [_maxChunkChars] a la limite.
List<String> _splitWord(String word) => <String>[
  for (int i = 0; i < word.length; i += _maxChunkChars)
    word.substring(
      i,
      i + _maxChunkChars > word.length ? word.length : i + _maxChunkChars,
    ),
];
