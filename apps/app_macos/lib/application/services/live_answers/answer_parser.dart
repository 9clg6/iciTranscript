import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';

/// Réponse réservée du modèle : rien d'utile à dire, ou pas une question
/// adressée à l'utilisateur. Une réponse qui COMMENCE par ce jeton est un
/// refus, quoi qui suive.
const String kNoAnswerToken = 'NO_ANSWER';

/// Habillage autour du jeton réservé (markdown, citation, guillemets).
final RegExp _tokenDressing = RegExp('^[\\s>*_`"\'«»“”]+');

/// [raw] commence par [kNoAnswerToken], une fois l'habillage retiré.
bool isDeclined(String raw) =>
    raw.replaceFirst(_tokenDressing, '').startsWith(kNoAnswerToken);

/// Début de flux qui peut encore devenir le jeton (habillé) : à ne pas
/// afficher.
bool mayBecomeDeclined(String raw) {
  final String t = raw.replaceFirst(_tokenDressing, '');
  return t.startsWith(kNoAnswerToken) || kNoAnswerToken.startsWith(t);
}

/// Puces gardées sous la phrase de tête.
const int kMaxBullets = 3;

/// Réponse lue selon le contrat de sortie.
class ParsedAnswer {
  /// Crée une [ParsedAnswer].
  const ParsedAnswer({
    required this.declined,
    required this.headline,
    required this.bullets,
    required this.sources,
    required this.truncated,
    this.shortened = false,
  });

  static const ParsedAnswer _declined = ParsedAnswer(
    declined: true,
    headline: '',
    bullets: <String>[],
    sources: <AnswerSource>[],
    truncated: false,
  );

  /// Le modèle a refusé : `NO_ANSWER`, ou une phrase qui dit que
  /// l'information manque ou que ce n'est pas une question.
  final bool declined;

  /// Phrase de tête.
  final String headline;

  /// Puces, sans leur marqueur, au plus [kMaxBullets].
  final List<String> bullets;

  /// Extraits cités ; `[S<i>]` du texte renvoie à `sources[i - 1]`.
  final List<AnswerSource> sources;

  /// Le texte s'arrête au milieu d'une phrase.
  final bool truncated;

  /// Des lignes reçues ne sont pas montrées (au-delà de la tête et de
  /// [kMaxBullets] puces, ou un autre bloc).
  final bool shortened;

  /// Réponse affichée et sauvegardée : la tête puis une puce par ligne.
  String get text => <String>[
    if (headline.isNotEmpty) headline,
    for (final String b in bullets) '- $b',
  ].join('\n');
}

/// Repère de citation `[S<n>]`.
final RegExp kCitation = RegExp(r'\[S(\d+)\]');

final RegExp _bulletMarker = RegExp(r'^([-*•]|\d+[.)])\s+');
final RegExp _finalStop = RegExp(r'[.!?…»")]$');
final RegExp _trailingCitations = RegExp(r'(\s*\[S\d+\])+\s*$');

/// Lit [raw], la réponse complète d'un modèle, contre les [excerpts] qu'il
/// a reçus (l'extrait n° i, à partir de 1, se cite `[S<i>]`). Une seule
/// lecture pour tous les fournisseurs, faite pour les sorties réelles d'un
/// petit modèle local : refus en prose, jeton au milieu, citations mal
/// formées, préambules, réponses trop longues.
///
/// Étapes : refus en tête ; lignes portant le jeton retirées ; citations
/// et préambules nettoyés ; bloc gardé (le premier qui cite un extrait
/// fourni) ; tête + [kMaxBullets] puces ; refus en prose ; citations
/// renumérotées dans l'ordre de première citation (inconnues retirées).
ParsedAnswer parseAnswer(String raw, List<DocumentExcerpt> excerpts) {
  final String trimmed = raw.trim();
  if (isDeclined(trimmed)) return ParsedAnswer._declined;

  final List<String> cleaned = <String>[
    for (final String l in trimmed.split('\n'))
      if (!l.contains(kNoAnswerToken)) _clean(l, excerpts.length),
  ];
  final List<List<String>> blocks = _blocks(cleaned);
  if (blocks.isEmpty) return ParsedAnswer._declined;
  final List<String> block = blocks.firstWhere(
    (List<String> b) => b.any(kCitation.hasMatch),
    orElse: () => blocks.first,
  );
  final List<String> lines = <String>[
    for (final String l in block) l.replaceFirst(_bulletMarker, '').trim(),
  ].where((String l) => l.isNotEmpty).toList();
  if (lines.isEmpty || _isRefusal(lines)) return ParsedAnswer._declined;
  final List<String> kept = lines.take(kMaxBullets + 1).toList();

  final List<AnswerSource> sources = <AnswerSource>[];
  final Map<int, int> renumber = <int, int>{};
  String cite(String line) =>
      line.replaceAllMapped(RegExp(r'\s*\[S(\d+)\]'), (Match m) {
        final int n = int.parse(m[1]!);
        final int to = renumber.putIfAbsent(n, () {
          final DocumentExcerpt e = excerpts[n - 1];
          sources.add(
            AnswerSource(
              documentId: e.documentId,
              title: e.documentTitle,
              excerpt: e.text,
            ),
          );
          return sources.length;
        });
        return '${m[0]!.substring(0, m[0]!.indexOf('['))}[S$to]';
      }).trim();
  final List<String> cited = kept.map(cite).toList();
  final bool emptyLastBullet = RegExp(
    r'(^|\n)\s*([-*•]|\d+[.)])\s*$',
  ).hasMatch(trimmed);
  return ParsedAnswer(
    declined: false,
    headline: cited.first,
    bullets: cited.skip(1).toList(),
    sources: sources,
    truncated:
        emptyLastBullet ||
        _looksCut(cited.last.replaceFirst(_trailingCitations, '')),
    shortened:
        lines.length > kept.length ||
        blocks.length > 1 && blocks.any((List<String> b) => b != block),
  );
}

/// Groupe entre crochets ou parenthèses fait de tags `S<n>`, d'heures,
/// « User » ou « Speaker n » : remplacé par les citations canoniques
/// fournies, le reste retiré.
final RegExp _citationGroup = RegExp(
  r'(\s*)([\[(])([^\[\]()]*|\[[^\[\]]*\])([\])])',
);
final RegExp _tag = RegExp(r'\bS(\d+)\b');
final RegExp _time = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b');
final RegExp _documentTag = RegExp(r'\b(?:the )?documents? S(\d+)\b');
final RegExp _preamble = RegExp(
  r"^\s*(User's response|User|Answer|Response|Réponse)\s*:\s*",
  caseSensitive: false,
);

/// Une ligne nettoyée : citations canoniques vers [count] extraits
/// fournis, heures et préambule retirés.
String _clean(String line, int count) {
  String canonical(Iterable<RegExpMatch> tags) => <String>[
    for (final RegExpMatch t in tags)
      if (int.parse(t[1]!) case final int n when n >= 1 && n <= count) '[S$n]',
  ].join(' ');

  String out = line.replaceAllMapped(_documentTag, (Match m) => '[S${m[1]}]');
  // Deux passes : `([S1])` devient `[S1]` après la première.
  for (int pass = 0; pass < 2; pass++) {
    out = out.replaceAllMapped(_citationGroup, (Match m) {
      final String inner = m[3]!;
      final String rest = inner
          .replaceAll(kCitation, '')
          .replaceAll(_tag, '')
          .replaceAll(_time, '')
          .replaceAll(RegExp(r'\b(User|Speaker \d+)\b'), '')
          .replaceAll(RegExp(r'[\s,;:]'), '');
      if (rest.isNotEmpty) return m[0]!;
      final String tags = canonical(_tag.allMatches(inner));
      return tags.isEmpty ? '' : '${m[1]}$tags';
    });
  }
  final bool bullet = _bulletMarker.hasMatch(out.trimLeft());
  final String body = out.trimLeft().replaceFirst(_bulletMarker, '');
  final String withoutPreamble = body.replaceFirst(_preamble, '').trim();
  if (withoutPreamble.isEmpty) return '';
  return bullet ? '- $withoutPreamble' : withoutPreamble;
}

/// Blocs séparés par une ligne vide, chacun commençant par une ligne qui
/// n'est pas une puce (une puce après une ligne vide continue le bloc).
List<List<String>> _blocks(List<String> lines) {
  final List<List<String>> blocks = <List<String>>[];
  bool afterBlank = false;
  for (final String l in lines) {
    if (l.trim().isEmpty) {
      afterBlank = true;
      continue;
    }
    if (blocks.isEmpty ||
        (afterBlank && !_bulletMarker.hasMatch(l.trimLeft()))) {
      blocks.add(<String>[]);
    }
    blocks.last.add(l);
    afterBlank = false;
  }
  return blocks;
}

/// Phrases qui disent que l'information manque, ou que ce n'est pas une
/// question pour l'utilisateur. Un état du monde (« not yet approved »)
/// n'en est pas une.
final RegExp _refusal = RegExp(
  r"not (explicitly )?(given|provided|stated|indicated|mentioned|specified)"
  r"|(documents?|excerpts?) do(es)? not (mention|contain)"
  r"|did not specify"
  r"|no specific\b[^.]*\b(given|available)"
  r"|n'est pas (donné|indiqué|précisé|mentionné)"
  r"|n'ont pas été mentionné"
  r"|non (spécifié|indiqué|précisé)"
  r"|ne connaît pas"
  r"|aucune information"
  r"|not a question|is a comment",
  caseSensitive: false,
);

/// Refus en prose : la phrase qui répond (la première de la tête) le dit ;
/// si la tête est un titre suivi de puces, toute ligne compte.
bool _isRefusal(List<String> lines) {
  final String head = lines.first.replaceFirst(_trailingCitations, '');
  final bool title =
      lines.length > 1 && (!_finalStop.hasMatch(head) || head.endsWith(':'));
  if (title) return lines.any(_refusal.hasMatch);
  return _refusal.hasMatch(lines.first.split(RegExp(r'(?<=[.!?])\s')).first);
}

/// Mots outils après lesquels une ligne ne peut pas finir.
const Set<String> _functionWords = <String>{
  'de', 'du', 'des', 'le', 'la', 'les', 'un', 'une', 'et', 'ou', 'à', 'au', //
  'aux', 'pour', 'par', 'avec', 'en', 'sur', 'the', 'a', 'an', 'of', 'to', //
  'and', 'or', 'for', 'with', 'in', 'on', 'at', //
};

/// Dernière ligne coupée ? Sans signal de fin de longueur du fournisseur :
/// seulement si elle finit sur un signe de suite (, ; : - – ou parenthèse
/// ouverte) ou sur un mot outil. Une ligne finie par un mot plein est
/// complète, même sans point.
bool _looksCut(String line) {
  if (_finalStop.hasMatch(line)) return false;
  if (RegExp(r'[,;:\-–(]$').hasMatch(line)) return true;
  if ('('.allMatches(line).length > ')'.allMatches(line).length) {
    return true;
  }
  final String lastWord = line.split(RegExp(r'\s+')).last.toLowerCase();
  return _functionWords.contains(lastWord);
}
