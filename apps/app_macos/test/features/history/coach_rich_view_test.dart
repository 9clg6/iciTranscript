import 'dart:ui' show Tristate;

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';

import '../../helpers/localized_app.dart';

/// Coach anglais plus riche (PR 1 : présentation seule).
///
/// Besoin (Clément, 2026-11-27) : « citer les erreurs, corriger, donner du
/// vocabulaire, rayer, coloré, tout le nécessaire pour progresser à chaque
/// réunion ». Design A choisi : bilan chiffré par type en haut ; corrections
/// groupées par type, repliables ; seuls les MOTS fautifs barrés en rouge
/// doux (`o.danger`), les mots corrigés en vert (`o.accent`), la couleur
/// jamais seul signal (barré / gras) ; « Vocabulaire à retenir » tiré des
/// corrections vocabulaire / expression ; une correction identique à
/// l'original est masquée. Clair et sombre : jetons du thème.
///
/// Choix posés ici (le besoin ne les tranche pas) :
/// - ordre fixe des types : Grammaire, Expression, Vocabulaire, Conjugaison,
///   puis Style, Suggestion, puis les catégories libres (ordre d'arrivée) ;
///   ni l'ordre d'arrivée ni l'ordre des nombres ;
/// - « grammar » et « Grammaire » sont le même type (comme
///   `coachCategoryKey`) ;
/// - groupes ouverts à l'ouverture de la note ;
/// - toutes les corrections masquées : « Aucune correction », comme une
///   note sans correction ;
/// - en-tête de groupe : bouton accessible avec état ouvert / fermé, qui
///   s'ouvre et se ferme aussi au clavier.
///
/// API supposée (pour le code) :
/// - `CoachFeedbackView(feedback:, onRetry:)` inchangé ;
/// - bilan sous `ValueKey<String>('coach-recap')` : pour chaque type, son
///   libellé (`coachCategoryLabel`) puis son nombre ;
/// - « Vocabulaire à retenir » sous `ValueKey<String>('coach-vocabulary')`,
///   titre tiré de fr.json, valeur « Vocabulaire à retenir » ;
/// - en-tête de groupe : nœud sémantique dont le nom contient le libellé
///   puis le nombre, avec l'état `expanded` (vrai / faux) ;
/// - chaque ligne garde l'original entier dans un seul texte (Text ou
///   Text.rich), et la version corrigée dans un autre.
///
/// Phrases anglaises inventées.
void main() {
  EnglishCorrectionEntity fix(
    String original,
    String corrected,
    String category, {
    String explanation = 'Explication courte.',
    int? at,
  }) => EnglishCorrectionEntity(
    original: original,
    corrected: corrected,
    category: category,
    explanation: explanation,
    timestampMs: at,
  );

  Future<void> pumpCoach(
    WidgetTester tester,
    EnglishFeedbackEntity feedback, {
    Brightness brightness = Brightness.light,
    VoidCallback? onRetry,
  }) => pumpLocalized(
    tester,
    Theme(
      data: buildOatsTheme(brightness),
      child: SingleChildScrollView(
        child: CoachFeedbackView(feedback: feedback, onRetry: onRetry),
      ),
    ),
    size: const Size(1280, 2600),
  );

  /// Texte lu (ordre de l'arbre) sous [scope].
  String textUnder(WidgetTester tester, Finder scope) => tester
      .widgetList<RichText>(
        find.descendant(of: scope, matching: find.byType(RichText)),
      )
      .map((RichText r) => r.text.toPlainText())
      .join(' ');

  /// Rectangle d'un nœud sémantique dans la fenêtre (pixels logiques).
  Rect globalRect(SemanticsNode node) {
    Rect r = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform != null) r = MatrixUtils.transformRect(n.transform!, r);
    }
    final double dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    return Rect.fromLTRB(
      r.left / dpr,
      r.top / dpr,
      r.right / dpr,
      r.bottom / dpr,
    );
  }

  /// En-tête de groupe repliable dont le nom contient [label].
  SemanticsFinder header(String label) =>
      find.semantics.byPredicate((SemanticsNode n) {
        final SemanticsData d = n.getSemanticsData();
        return d.label.contains(label) &&
            d.flagsCollection.isExpanded != Tristate.none;
      });

  SemanticsData headerData(String label) =>
      header(label).evaluate().single.getSemanticsData();

  /// Libellé suivi de son nombre : le premier nombre après le libellé
  /// (nombre seul ou forme « 3 corrections » de fr.json).
  RegExp labelThenCount(String label, int count) =>
      RegExp('${RegExp.escape(label)}[^0-9]*(?<!\\d)$count(?!\\d)');

  String label(String category) => coachCategoryLabel(category);

  group('bilan en haut', () {
    // Ordre d'arrivée et ordre des nombres différents de l'ordre fixe.
    final EnglishFeedbackEntity mixed = EnglishFeedbackEntity(
      overall: 'Bon niveau.',
      corrections: <EnglishCorrectionEntity>[
        fix(
          'Yesterday we decide to stop',
          'Yesterday we decided to stop',
          'conjugation',
        ),
        fix('We must take a choice', 'We must make a choice', 'vocabulary'),
        fix('She go to the office', 'She goes to the office', 'conjugation'),
        fix('Can you borrow me a pen', 'Can you lend me a pen', 'vocabulary'),
        fix('They was late again', 'They were late again', 'conjugation'),
        fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
        fix('We discussed about costs', 'We discussed costs', 'Grammaire'),
        fix(
          'He arrive tomorrow morning',
          'He arrives tomorrow morning',
          'conjugation',
        ),
        fix('Please do a call later', 'Please make a call later', 'vocabulary'),
        fix(
          'Looking forward to meet you',
          'Looking forward to meeting you',
          'expression',
        ),
        // Identique à l'original : ni montrée ni comptée.
        fix('The plan is ready', 'the plan is ready ', 'grammar'),
      ],
    );

    testWidgets('un nombre par type présent, dans l\'ordre fixe, au-dessus '
        'des corrections', (WidgetTester tester) async {
      await pumpCoach(tester, mixed);

      final Finder recap = find.byKey(const ValueKey<String>('coach-recap'));
      expect(recap, findsOneWidget);
      final String text = textUnder(tester, recap);
      final List<(String, int)> expected = <(String, int)>[
        (label('grammar'), 2),
        (label('expression'), 1),
        (label('vocabulary'), 3),
        (label('conjugation'), 4),
      ];
      int last = -1;
      for (final (String name, int count) in expected) {
        final RegExpMatch? m = labelThenCount(name, count).firstMatch(text);
        expect(m, isNotNull, reason: '« $name $count » dans « $text »');
        expect(m!.start, greaterThan(last), reason: 'ordre fixe : « $text »');
        last = m.start;
      }
      expect(
        tester.getTopLeft(recap).dy,
        lessThan(
          tester.getTopLeft(find.textContaining('I am agree with Paul')).dy,
        ),
      );
    });

    testWidgets('un type absent n\'est pas dans le bilan', (
      WidgetTester tester,
    ) async {
      await pumpCoach(tester, mixed);

      final Finder recap = find.byKey(const ValueKey<String>('coach-recap'));
      expect(recap, findsOneWidget);
      final String text = textUnder(tester, recap);
      expect(text, contains(label('grammar')));
      expect(text, isNot(contains(label('style'))));
      expect(text, isNot(contains(label(''))));
    });

    testWidgets('une catégorie libre du modèle : telle quelle, après les '
        'types connus', (WidgetTester tester) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('I red the book', 'I read the book', 'pronunciation'),
            fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
          ],
        ),
      );

      final String text = textUnder(
        tester,
        find.byKey(const ValueKey<String>('coach-recap')),
      );
      final RegExpMatch? free = RegExp(
        r'pronunciation[^0-9]*(?<!\d)1(?!\d)',
      ).firstMatch(text);
      expect(free, isNotNull, reason: text);
      expect(
        labelThenCount(label('grammar'), 1).firstMatch(text)!.start,
        lessThan(free!.start),
      );
    });
  });

  group('corrections groupées par type', () {
    final EnglishFeedbackEntity two = EnglishFeedbackEntity(
      corrections: <EnglishCorrectionEntity>[
        fix(
          'Looking forward to meet you',
          'Looking forward to meeting you',
          'expression',
          at: 30000,
        ),
        fix('I am agree with Paul', 'I agree with Paul', 'grammar', at: 65000),
        fix(
          'Is it possible to discuss about it',
          'Is it possible to discuss it',
          'expression',
        ),
        fix('We discussed about costs', 'We discussed costs', 'grammar'),
        fix('She don\'t know yet', 'She doesn\'t know yet', 'grammaire'),
      ],
    );

    testWidgets('un en-tête par type (libellé + nombre), dans l\'ordre fixe, '
        'chaque correction sous le sien', (WidgetTester tester) async {
      await pumpCoach(tester, two);

      final String g = label('grammar');
      final String e = label('expression');
      expect(header(g), findsOne);
      expect(header(e), findsOne);
      expect(headerData(g).label, matches(labelThenCount(g, 3)));
      expect(headerData(e).label, matches(labelThenCount(e, 2)));

      final double gTop = globalRect(header(g).evaluate().single).top;
      final double eTop = globalRect(header(e).evaluate().single).top;
      expect(gTop, lessThan(eTop), reason: 'Grammaire avant Expression');
      double top(String text) =>
          tester.getTopLeft(find.textContaining(text)).dy;
      for (final String s in <String>[
        'I am agree with Paul',
        'We discussed about costs',
        'She don\'t know yet',
      ]) {
        expect(top(s), inExclusiveRange(gTop, eTop), reason: s);
      }
      for (final String s in <String>[
        'Looking forward to meet you',
        'Is it possible to discuss about it',
      ]) {
        expect(top(s), greaterThan(eTop), reason: s);
      }
    });

    testWidgets('groupes ouverts par défaut : toutes les corrections '
        'visibles', (WidgetTester tester) async {
      await pumpCoach(tester, two);

      expect(
        headerData(label('grammar')).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      expect(
        headerData(label('expression')).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      for (final EnglishCorrectionEntity c in two.corrections) {
        expect(
          find.textContaining(c.original).hitTestable(),
          findsOneWidget,
          reason: c.original,
        );
      }
    });

    testWidgets('cliquer l\'en-tête replie le groupe (les autres et le bilan '
        'restent), recliquer le rouvre', (WidgetTester tester) async {
      await pumpCoach(tester, two);
      final String g = label('grammar');

      await tester.tapAt(globalRect(header(g).evaluate().single).center);
      await tester.pumpAndSettle();

      expect(headerData(g).flagsCollection.isExpanded, Tristate.isFalse);
      for (final String s in <String>[
        'I am agree with Paul',
        'We discussed about costs',
      ]) {
        expect(find.textContaining(s).hitTestable(), findsNothing, reason: s);
      }
      expect(
        find.textContaining('Looking forward to meet you').hitTestable(),
        findsOneWidget,
      );
      expect(
        textUnder(tester, find.byKey(const ValueKey<String>('coach-recap'))),
        matches(labelThenCount(g, 3)),
      );

      await tester.tapAt(globalRect(header(g).evaluate().single).center);
      await tester.pumpAndSettle();

      expect(headerData(g).flagsCollection.isExpanded, Tristate.isTrue);
      expect(
        find.textContaining('I am agree with Paul').hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('au clavier seul : Tab jusqu\'à l\'en-tête, Espace replie', (
      WidgetTester tester,
    ) async {
      await pumpCoach(tester, two);
      final String e = label('expression');

      for (int i = 0; i < 30; i++) {
        if (headerData(e).flagsCollection.isFocused == Tristate.isTrue) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(headerData(e).flagsCollection.isFocused, Tristate.isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(headerData(e).flagsCollection.isExpanded, Tristate.isFalse);
      expect(
        find.textContaining('Looking forward to meet you').hitTestable(),
        findsNothing,
      );
    });

    testWidgets('l\'heure dans la note reste sur sa correction', (
      WidgetTester tester,
    ) async {
      await pumpCoach(tester, two);

      expect(find.textContaining('01:05'), findsOneWidget);
      expect(find.textContaining('00:30'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);
    });
  });

  group('diff mot à mot', () {
    /// Styles effectifs des morceaux de texte qui contiennent le mot [word].
    List<TextStyle> stylesOf(WidgetTester tester, String word) {
      final RegExp whole = RegExp(
        '(?<![A-Za-z\'])${RegExp.escape(word)}(?![A-Za-z\'])',
      );
      final List<TextStyle> found = <TextStyle>[];
      void walk(InlineSpan span, TextStyle inherited) {
        final TextStyle style = inherited.merge(span.style);
        if (span is TextSpan) {
          if (whole.hasMatch(span.text ?? '')) found.add(style);
          for (final InlineSpan child
              in span.children ?? const <InlineSpan>[]) {
            walk(child, style);
          }
        }
      }

      for (final RichText r in tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(CoachFeedbackView),
          matching: find.byType(RichText),
        ),
      )) {
        walk(r.text, const TextStyle());
      }
      expect(found, isNotEmpty, reason: '« $word » introuvable');
      return found;
    }

    bool struck(TextStyle s) =>
        s.decoration?.contains(TextDecoration.lineThrough) ?? false;
    int weight(TextStyle s) => (s.fontWeight ?? FontWeight.w400).value;

    final EnglishFeedbackEntity one = EnglishFeedbackEntity(
      corrections: <EnglishCorrectionEntity>[
        fix(
          'He have sent the deck',
          'He has sent the deck',
          'grammar',
          explanation: 'Accord du verbe au singulier.',
        ),
      ],
    );

    for (final Brightness b in Brightness.values) {
      final Oats o = b == Brightness.dark ? Oats.dark : Oats.light;

      testWidgets('${b.name} : seul le mot retiré est barré, couleur danger', (
        WidgetTester tester,
      ) async {
        await pumpCoach(tester, one, brightness: b);

        for (final TextStyle s in stylesOf(tester, 'have')) {
          expect(struck(s), isTrue, reason: 'barré');
          expect(s.color, o.danger);
        }
      });

      testWidgets(
        '${b.name} : seul le mot ajouté est en gras, couleur accent',
        (WidgetTester tester) async {
          await pumpCoach(tester, one, brightness: b);

          for (final TextStyle s in stylesOf(tester, 'has')) {
            expect(weight(s), greaterThanOrEqualTo(600), reason: 'gras');
            expect(s.color, o.accent);
            expect(struck(s), isFalse);
          }
        },
      );

      testWidgets('${b.name} : les mots inchangés restent normaux, des deux '
          'côtés', (WidgetTester tester) async {
        await pumpCoach(tester, one, brightness: b);

        for (final String word in <String>['sent', 'deck']) {
          final List<TextStyle> styles = stylesOf(tester, word);
          expect(
            styles.length,
            greaterThanOrEqualTo(2),
            reason: 'original + corrigé',
          );
          for (final TextStyle s in styles) {
            expect(struck(s), isFalse, reason: '« $word » barré');
            expect(
              weight(s),
              lessThanOrEqualTo(500),
              reason: '« $word » en gras',
            );
            expect(s.color, isNot(o.danger), reason: word);
            expect(s.color, isNot(o.accent), reason: word);
          }
        }
      });
    }

    testWidgets('la phrase dite et la meilleure tournure se lisent encore en '
        'entier', (WidgetTester tester) async {
      await pumpCoach(tester, one);

      expect(find.textContaining('He have sent the deck'), findsOneWidget);
      expect(find.textContaining('He has sent the deck'), findsOneWidget);
    });
  });

  group('correction identique à l\'original', () {
    testWidgets('ni montrée ni comptée', (WidgetTester tester) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('We are ready to start', ' we are READY to start ', 'grammar'),
            fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
            fix('Thanks for the call', 'thanks for the call', 'expression'),
          ],
        ),
      );

      expect(
        find.textContaining(RegExp('ready to start', caseSensitive: false)),
        findsNothing,
      );
      expect(
        find.textContaining(
          RegExp('thanks for the call', caseSensitive: false),
        ),
        findsNothing,
      );
      final String recap = textUnder(
        tester,
        find.byKey(const ValueKey<String>('coach-recap')),
      );
      expect(recap, matches(labelThenCount(label('grammar'), 1)));
      expect(recap, isNot(contains(label('expression'))));
      expect(
        headerData(label('grammar')).label,
        matches(labelThenCount(label('grammar'), 1)),
      );
      expect(header(label('expression')), findsNothing);
    });

    testWidgets('toutes identiques : « Aucune correction », ni bilan ni '
        'groupe', (WidgetTester tester) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          overall: 'Très bon niveau.',
          corrections: <EnglishCorrectionEntity>[
            fix('Thanks for the call', 'thanks for the call', 'expression'),
            fix('See you soon', ' see you soon', 'vocabulary'),
          ],
        ),
      );

      expect(find.text('history.detail.coach_perfect'.tr()), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('coach-recap')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('coach-vocabulary')),
        findsNothing,
      );
      expect(
        find.textContaining(RegExp('see you soon', caseSensitive: false)),
        findsNothing,
      );
      expect(
        find.textContaining(
          RegExp('thanks for the call', caseSensitive: false),
        ),
        findsNothing,
      );
    });
  });

  group('vocabulaire à retenir', () {
    final String title = '${kOpen}Vocabulaire à retenir$kClose';
    final Finder section = find.byKey(
      const ValueKey<String>('coach-vocabulary'),
    );
    Finder inSection(Pattern p) =>
        find.descendant(of: section, matching: find.textContaining(p));

    testWidgets('tiré des corrections vocabulaire et expression : la '
        'tournure corrigée et son explication', (WidgetTester tester) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix(
              'I am agree with Paul',
              'I agree with Paul',
              'grammar',
              explanation: 'Verbe sans « am ».',
            ),
            fix(
              'take a decision',
              'make a decision',
              'vocabulary',
              explanation: 'On dit « make a decision ».',
            ),
            fix(
              'Looking forward to meet you',
              'Looking forward to meeting you',
              'expression',
              explanation: '« to » suivi de -ing.',
            ),
          ],
        ),
      );

      expect(find.text(title), findsOneWidget);
      expect(section, findsOneWidget);
      expect(inSection('make a decision'), findsWidgets);
      expect(inSection('On dit « make a decision ».'), findsOneWidget);
      expect(inSection('Looking forward to meeting you'), findsOneWidget);
      expect(inSection('« to » suivi de -ing.'), findsOneWidget);
      expect(inSection('I agree with Paul'), findsNothing, reason: 'grammaire');
      expect(inSection('Verbe sans « am ».'), findsNothing);
    });

    testWidgets('une même tournure (casse près) ne revient qu\'une fois', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix(
              'take a decision',
              'make a decision',
              'vocabulary',
              explanation: 'Première.',
            ),
            fix(
              'do a decision',
              'Make a Decision',
              'vocabulary',
              explanation: 'Seconde.',
            ),
          ],
        ),
      );

      final List<String> texts = tester
          .widgetList<RichText>(
            find.descendant(of: section, matching: find.byType(RichText)),
          )
          .map((RichText r) => r.text.toPlainText().toLowerCase())
          .where(
            (String t) => t.contains('make a decision') && !t.contains('«'),
          )
          .toList();
      expect(texts, hasLength(1), reason: '$texts');
      // Les deux corrections restent dans leur groupe.
      expect(find.textContaining('take a decision'), findsOneWidget);
      expect(find.textContaining('do a decision'), findsOneWidget);
    });

    testWidgets('une correction identique à l\'original n\'y est pas', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('take a decision', 'make a decision', 'vocabulary'),
            fix('on the other hand', 'On the other hand', 'expression'),
          ],
        ),
      );

      expect(inSection('make a decision'), findsWidgets);
      expect(
        inSection(RegExp('on the other hand', caseSensitive: false)),
        findsNothing,
      );
    });

    testWidgets('ni vocabulaire ni expression : pas de section', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
          ],
        ),
      );

      expect(find.text(title), findsNothing);
      expect(section, findsNothing);
    });
  });

  group('ce qui existait reste', () {
    testWidgets('le commentaire global, avec les corrections', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          overall: 'Bon niveau, attention aux temps.',
          corrections: <EnglishCorrectionEntity>[
            fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
          ],
        ),
      );

      expect(find.text('Bon niveau, attention aux temps.'), findsOneWidget);
    });

    testWidgets('rien en anglais à analyser : le dit, sans bilan', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        const EnglishFeedbackEntity(nothingToAnalyse: true),
      );

      expect(find.text('coach.nothing_to_analyse'.tr()), findsOneWidget);
      expect(find.text('history.detail.coach_perfect'.tr()), findsNothing);
      expect(find.byKey(const ValueKey<String>('coach-recap')), findsNothing);
    });

    testWidgets('partie non analysée : la mention et « Réessayer », qui '
        'relance', (WidgetTester tester) async {
      int retries = 0;
      await pumpCoach(
        tester,
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('I am agree with Paul', 'I agree with Paul', 'grammar'),
          ],
          unanalyzedSegmentIds: const <String>['seg-2'],
        ),
        onRetry: () => retries++,
      );

      expect(find.text('coach.unanalyzed'.tr()), findsOneWidget);
      await tester.tap(find.text('common.action.retry'.tr()));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('sans relance possible : la mention, pas de bouton', (
      WidgetTester tester,
    ) async {
      await pumpCoach(
        tester,
        const EnglishFeedbackEntity(unanalyzedSegmentIds: <String>['seg-2']),
      );

      expect(find.text('coach.unanalyzed'.tr()), findsOneWidget);
      expect(find.text('common.action.retry'.tr()), findsNothing);
    });
  });
}
