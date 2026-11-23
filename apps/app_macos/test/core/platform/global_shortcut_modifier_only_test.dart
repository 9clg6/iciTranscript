import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';

/// Raccourci de dictée « modificateurs seuls » (⌘⌥, sans autre touche) :
/// côté Dart du plugin Swift GlobalShortcutPlugin. Carbon
/// (RegisterEventHotKey) ne sait pas poser un raccourci sans touche : le
/// plugin surveille les modificateurs en global, ce qui demande la
/// permission Accessibilité.
///
/// Contrat (ajouté à celui de global_shortcut_channel_test.dart) :
///
/// MethodChannel `com.icitranscript/global_shortcut`
/// - `registerModifiers` {modifiers: int (masque Carbon : cmd 256, shift
///   512, option 2048, control 4096 ; au moins deux, dont ⌃, ⌥ ou ⌘),
///   holdMs: int (seuil d'appui, = `DictationController.holdThreshold`,
///   seule source de la valeur)} → null. Remplace le raccourci précédent (à
///   touche ou modificateurs seuls). Lève PlatformException
///   `ACCESSIBILITY_REQUIRED` si l'Accessibilité n'est pas accordée : rien
///   n'est posé (jamais un raccourci posé mais muet). Dart :
///   `registerModifiers(modifiers:, holdThreshold:)` rend vrai si posé, faux
///   sinon (refus ou plugin absent), sans lever.
/// - `unregister` retire aussi la surveillance des modificateurs.
/// - `setCancelKeyEnabled` : inchangé (Échap pendant une dictée).
///
/// EventChannel `com.icitranscript/global_shortcut_events`. Un accord n'agit
/// qu'une fois su être le nôtre (revue de la PR #29 : ⌘⌥I, ⌘⌥Échap, ⌘⌥D ne
/// doivent ni allumer le point orange du micro ni couper une phrase de
/// réunion). Dès que exactement les modificateurs choisis sont enfoncés
/// (aucun autre modificateur, aucune autre touche), l'appui est INDÉCIS :
/// - pendant `holdMs`, une autre touche (Échap comprise) ou un bouton de
///   souris → RIEN n'est émis pour cet appui, ni maintenant ni au
///   relâchement ;
/// - relâché avant `holdMs` sans rien d'autre → `tapped` (nouveau) : appui
///   bref, bascule ;
/// - tenu `holdMs` sans rien d'autre → `pressed`, émis au seuil : appui
///   maintenu confirmé ; puis `released` au relâchement ;
/// - après `pressed`, une autre touche ou un clic → `aborted` (aucun
///   `released` ne suit ; un `released` égaré est ignoré par la dictée).
///   Échap tapée avec les modificateurs tenus donne `aborted` ou rien,
///   jamais `cancel` ;
/// - `cancel` : inchangé, Échap pendant une dictée, modificateurs relâchés.
///
/// Le passage de `tapped` et `aborted` dans le flux Dart est épinglé dans
/// global_shortcut_channel_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel method = MethodChannel(
    'com.icitranscript/global_shortcut',
  );
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(method, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  test('registerModifiers envoie le masque et le seuil d appui, sans code de '
      'touche ; vrai si posé', () async {
    answer((_) => null);

    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 256 | 2048,
      holdThreshold: const Duration(milliseconds: 300),
    );

    expect(ok, isTrue);
    expect(calls.single.method, 'registerModifiers');
    expect(calls.single.arguments, <String, Object>{
      'modifiers': 2304,
      'holdMs': 300,
    });
  });

  test('Accessibilité absente : faux, sans lever', () async {
    answer((_) => throw PlatformException(code: 'ACCESSIBILITY_REQUIRED'));

    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 2304,
      holdThreshold: const Duration(milliseconds: 300),
    );

    expect(ok, isFalse);
  });

  test('plugin absent : faux, sans lever', () async {
    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 2304,
      holdThreshold: const Duration(milliseconds: 300),
    );

    expect(ok, isFalse);
  });
}
