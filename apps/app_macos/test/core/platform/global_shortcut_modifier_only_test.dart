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
///   512, option 2048, control 4096 ; au moins deux, dont ⌃, ⌥ ou ⌘)} →
///   null. Remplace le raccourci précédent (à touche ou modificateurs
///   seuls). Lève PlatformException `ACCESSIBILITY_REQUIRED` si
///   l'Accessibilité n'est pas accordée : rien n'est posé (jamais un
///   raccourci posé mais muet). Dart : `registerModifiers(modifiers:)` rend
///   vrai si posé, faux sinon (refus ou plugin absent), sans lever.
/// - `unregister` retire aussi la surveillance des modificateurs.
/// - `setCancelKeyEnabled` : inchangé (Échap pendant une dictée).
///
/// EventChannel `com.icitranscript/global_shortcut_events`, mêmes types :
/// - `pressed` : exactement les modificateurs choisis sont enfoncés (aucun
///   autre modificateur, aucune autre touche) ;
/// - `released` : l'un d'eux est relâché après un `pressed`, sans autre
///   touche entre-temps ;
/// - `aborted` (nouveau) : une touche autre qu'un modificateur (Échap
///   comprise) est enfoncée pendant que les modificateurs sont tenus après
///   un `pressed` : l'utilisateur tape un raccourci d'une autre app (⌘⌥Échap,
///   ⌘⌥D). Aucun `released` ne suit pour cet appui ; un `released` égaré est
///   ignoré par la dictée. Échap tapée avec les modificateurs tenus donne
///   `aborted`, jamais `cancel` ;
/// - `cancel` : inchangé, Échap pendant une dictée, modificateurs relâchés.
///
/// Le passage de `aborted` dans le flux Dart est épinglé dans
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

  test('registerModifiers envoie le masque seul, sans code de touche ; vrai '
      'si posé', () async {
    answer((_) => null);

    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 256 | 2048,
    );

    expect(ok, isTrue);
    expect(calls.single.method, 'registerModifiers');
    expect(calls.single.arguments, <String, Object>{'modifiers': 2304});
  });

  test('Accessibilité absente : faux, sans lever', () async {
    answer((_) => throw PlatformException(code: 'ACCESSIBILITY_REQUIRED'));

    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 2304,
    );

    expect(ok, isFalse);
  });

  test('plugin absent : faux, sans lever', () async {
    final bool ok = await GlobalShortcutChannel().registerModifiers(
      modifiers: 2304,
    );

    expect(ok, isFalse);
  });
}
