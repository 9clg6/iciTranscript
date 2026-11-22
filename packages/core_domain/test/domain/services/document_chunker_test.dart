import 'package:core_domain/domain/services/document_chunker.dart';
import 'package:test/test.dart';

/// Decoupage d'un document texte / markdown en morceaux d'environ 800 a 1200
/// caracteres, sur les limites de paragraphe, sans couper un mot, sans
/// morceau vide, en couvrant tout le texte dans l'ordre.

/// Paragraphe d'environ [chars] caracteres, mots distincts et numerotes pour
/// verifier l'ordre (`p3w12`), termine par un point.
String _paragraph(int index, int chars) {
  final StringBuffer b = StringBuffer();
  int w = 0;
  while (b.length < chars) {
    if (b.isNotEmpty) b.write(' ');
    b.write('p${index}w$w${w.isEven ? 'abc' : 'é'}');
    w++;
  }
  b.write('.');
  return b.toString();
}

List<String> _words(String text) =>
    text.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();

void main() {
  test('un texte vide ou blanc ne donne aucun morceau', () {
    expect(chunkDocument(''), isEmpty);
    expect(chunkDocument('  \n\n \t '), isEmpty);
  });

  test('un texte court donne un seul morceau, sans les blancs autour', () {
    expect(
      chunkDocument('\n\n# Budget\n\nLe budget 2027 est validé.\n'),
      <String>['# Budget\n\nLe budget 2027 est validé.'],
    );
  });

  test('les paragraphes sont regroupés en morceaux de 800 à 1200 caractères',
      () {
    final List<String> paragraphs = <String>[
      for (int i = 0; i < 20; i++) _paragraph(i, 290),
    ];
    final List<String> chunks = chunkDocument(paragraphs.join('\n\n'));

    expect(chunks.length, greaterThan(1));
    for (final String chunk in chunks.sublist(0, chunks.length - 1)) {
      expect(chunk.length, inInclusiveRange(800, 1200), reason: chunk);
    }
    expect(chunks.last.length, lessThanOrEqualTo(1200));
  });

  test('un morceau ne coupe pas un paragraphe qui tient dans la taille', () {
    final List<String> paragraphs = <String>[
      for (int i = 0; i < 20; i++) _paragraph(i, 290),
    ];
    final List<String> chunks = chunkDocument(paragraphs.join('\n\n'));

    final List<String> rebuilt = <String>[
      for (final String chunk in chunks)
        ...chunk.split(RegExp(r'\n\s*\n')).map((String p) => p.trim()),
    ];
    expect(rebuilt, paragraphs);
  });

  test('les morceaux couvrent tout le texte, dans l’ordre, sans couper de mot',
      () {
    final String text = <String>[
      '# Compte rendu',
      _paragraph(0, 150),
      '- point un\n- point deux\n- point trois',
      _paragraph(1, 700),
      _paragraph(2, 1000),
      _paragraph(3, 90),
      '## Suite',
      _paragraph(4, 2600),
      _paragraph(5, 400),
    ].join('\n\n');

    final List<String> chunks = chunkDocument(text);

    expect(_words(chunks.join(' ')), _words(text));
  });

  test('un paragraphe trop long est découpé en morceaux de 1200 au plus', () {
    final String text = _paragraph(0, 3500);

    final List<String> chunks = chunkDocument(text);

    expect(chunks.length, greaterThanOrEqualTo(3));
    for (final String chunk in chunks) {
      expect(chunk.length, lessThanOrEqualTo(1200));
    }
    expect(_words(chunks.join(' ')), _words(text));
  });

  test('aucun morceau n’est vide ni fait seulement de blancs', () {
    final String text = <String>[
      _paragraph(0, 1190),
      '',
      '   ',
      _paragraph(1, 1210),
      '\n\n\n',
      _paragraph(2, 10),
    ].join('\n\n');

    final List<String> chunks = chunkDocument(text);

    expect(chunks, isNotEmpty);
    for (final String chunk in chunks) {
      expect(chunk.trim(), isNotEmpty);
    }
    expect(_words(chunks.join(' ')), _words(text));
  });
}
