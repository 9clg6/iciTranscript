import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Marqueurs posés autour de chaque traduction chargée dans les tests.
///
/// Un texte affiché « ⟦Accueil⟧ » vient d'une clé de fr.json ; un texte
/// « Accueil » écrit en dur dans le code ne correspond à aucune attente.
const String kOpen = '⟦';
const String kClose = '⟧';

/// Lit assets/translations/fr.json (le cwd de `flutter test` est le package).
Map<String, dynamic> readFrJson() =>
    jsonDecode(File('assets/translations/fr.json').readAsStringSync())
        as Map<String, dynamic>;

/// Valeur de [key] (« a.b.c ») dans fr.json, null si absente.
Object? frValue(String key) {
  Object? node = readFrJson();
  for (final String part in key.split('.')) {
    if (node is! Map<String, dynamic> || !node.containsKey(part)) return null;
    node = node[part];
  }
  return node;
}

Object? _wrap(Object? node) {
  if (node is Map<String, dynamic>) {
    return node.map((String k, dynamic v) => MapEntry<String, dynamic>(k, _wrap(v)));
  }
  if (node is String) return '$kOpen$node$kClose';
  return node;
}

class _SentinelFrLoader extends AssetLoader {
  const _SentinelFrLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      _wrap(readFrJson()) as Map<String, dynamic>;
}

/// Enveloppe [child] dans EasyLocalization (fr, traductions marquées) et un
/// ProviderScope. Si [withMaterialApp], ajoute un MaterialApp localisé.
Widget localized({
  required Widget child,
  List<Override> overrides = const <Override>[],
  bool withMaterialApp = true,
}) {
  EasyLocalization.logger.enableBuildModes = [];
  return ProviderScope(
    overrides: overrides,
    child: EasyLocalization(
      supportedLocales: const <Locale>[Locale('fr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('fr'),
      startLocale: const Locale('fr'),
      saveLocale: false,
      assetLoader: const _SentinelFrLoader(),
      child: withMaterialApp
          ? Builder(
              builder: (BuildContext context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Scaffold(body: child),
              ),
            )
          : child,
    ),
  );
}

/// Pompe un widget localisé et attend le chargement des traductions.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
  bool withMaterialApp = true,
  Size size = const Size(1280, 800),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    localized(
      child: child,
      overrides: overrides,
      withMaterialApp: withMaterialApp,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// Vrai si le widget trouvé est dans la fenêtre et peut recevoir un clic.
bool isOnScreen(Finder finder) => finder.hitTestable().evaluate().isNotEmpty;
