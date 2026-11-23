import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Graisse effective du morceau de texte qui contient [needle] (Text ou
/// Text.rich : styles hérités le long des TextSpan).
FontWeight weightOf(WidgetTester tester, String needle) {
  FontWeight? found;
  void walk(InlineSpan span, TextStyle inherited) {
    final TextStyle style = inherited.merge(span.style);
    if (span is TextSpan) {
      if ((span.text ?? '').contains(needle)) {
        found ??= style.fontWeight ?? FontWeight.w400;
      }
      for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }
  }

  for (final RichText r in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(r.text, const TextStyle());
  }
  expect(found, isNotNull, reason: '« $needle » introuvable');
  return found!;
}
