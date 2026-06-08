import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Helpers communs pour les tests widget de l'application.
///
/// Fournit des methodes utilitaires pour simplifier la configuration
/// des tests et reduire la duplication de code.
class TestHelpers {
  TestHelpers._();

  /// Cree un [MaterialApp] wrape dans un [ProviderScope] pour les tests widget.
  ///
  /// [child] : le widget a tester.
  /// [overrides] : les overrides de providers pour injecter des mocks.
  static Widget createTestableWidget({
    required Widget child,
    List<Override> overrides = const <Override>[],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    );
  }

  /// Cree un [MaterialApp] wrape dans un [ProviderScope] avec un [Scaffold].
  ///
  /// Utile pour les widgets qui necessitent un [Scaffold] parent.
  static Widget createTestableWidgetWithScaffold({
    required Widget child,
    List<Override> overrides = const <Override>[],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  /// Pompe le widget et attend que tous les frames soient rendus.
  static Future<void> pumpAndSettle(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  /// Pompe le widget plusieurs fois pour les animations.
  static Future<void> pumpMultiple(WidgetTester tester, {int times = 5}) async {
    for (int i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
