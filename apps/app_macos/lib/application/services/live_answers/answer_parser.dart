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
  });

  /// Le modèle a refusé (`NO_ANSWER`).
  final bool declined;

  /// Phrase de tête.
  final String headline;

  /// Puces, sans leur marqueur, au plus [kMaxBullets].
  final List<String> bullets;

  /// Extraits cités ; `[S<i>]` du texte renvoie à `sources[i - 1]`.
  final List<AnswerSource> sources;

  /// Le texte s'arrête au milieu d'une phrase.
  final bool truncated;

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

/// Lit [raw], la réponse complète, contre les [excerpts] fournis au modèle
/// (l'extrait n° i, à partir de 1, se cite `[S<i>]`).
///
/// Citations vers un extrait non fourni : retirées du texte et des sources.
/// Les autres sont renumérotées dans l'ordre de première citation.
ParsedAnswer parseAnswer(String raw, List<DocumentExcerpt> excerpts) {
  final String trimmed = raw.trim();
  if (isDeclined(trimmed)) {
    return const ParsedAnswer(
      declined: true,
      headline: '',
      bullets: <String>[],
      sources: <AnswerSource>[],
      truncated: false,
    );
  }
  final List<String> lines = <String>[
    for (final String l in trimmed.split('\n'))
      if (l.trim().replaceFirst(_bulletMarker, '').trim() case final String t
          when t.isNotEmpty)
        t,
  ].take(kMaxBullets + 1).toList();

  final List<AnswerSource> sources = <AnswerSource>[];
  final Map<int, int> renumber = <int, int>{};
  String cite(String line) =>
      line.replaceAllMapped(RegExp(r'\s*\[S(\d+)\]'), (Match m) {
        final int n = int.parse(m[1]!);
        if (n < 1 || n > excerpts.length) return '';
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
  final List<String> cited = lines.map(cite).toList();
  final String last = cited.isEmpty
      ? ''
      : cited.last.replaceFirst(_trailingCitations, '');
  final bool emptyLastBullet = RegExp(
    r'(^|\n)\s*([-*•]|\d+[.)])\s*$',
  ).hasMatch(trimmed);
  return ParsedAnswer(
    declined: false,
    headline: cited.isEmpty ? '' : cited.first,
    bullets: cited.skip(1).toList(),
    sources: sources,
    truncated:
        emptyLastBullet ||
        (cited.length > 1
            ? _bulletLooksCut(last)
            : last.isNotEmpty && !_finalStop.hasMatch(last)),
  );
}

/// Mots outils après lesquels une puce ne peut pas finir.
const Set<String> _functionWords = <String>{
  'de', 'du', 'des', 'le', 'la', 'les', 'un', 'une', 'et', 'ou', 'à', 'au', //
  'aux', 'pour', 'par', 'avec', 'en', 'sur', 'the', 'a', 'an', 'of', 'to', //
  'and', 'or', 'for', 'with', 'in', 'on', 'at', //
};

/// Dernière puce coupée ? Sans signal de fin de longueur du fournisseur :
/// seulement si elle finit sur un signe de suite (, ; : - – ou parenthèse
/// ouverte) ou sur un mot outil. Une puce finie par un mot plein est
/// complète, même sans point.
bool _bulletLooksCut(String bullet) {
  if (_finalStop.hasMatch(bullet)) return false;
  if (RegExp(r'[,;:\-–(]$').hasMatch(bullet)) return true;
  if ('('.allMatches(bullet).length > ')'.allMatches(bullet).length) {
    return true;
  }
  final String lastWord = bullet.split(RegExp(r'\s+')).last.toLowerCase();
  return _functionWords.contains(lastWord);
}
