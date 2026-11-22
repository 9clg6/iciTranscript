import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';

/// Affichage du raccourci de dictée (T2) avec les caractères de la
/// disposition de clavier courante, pas la position QWERTY. Contrat Swift :
///
/// MethodChannel `com.icitranscript/global_shortcut`
/// - `keyLabel` {keyCode: int} → String? : caractères produits par la touche
///   dans la disposition courante (AZERTY : touche 13 → « Z »), sans
///   modificateur ; null si inconnu. Dart compose l'affichage :
///   modificateurs ⌃⌥⇧⌘ dans l'ordre d'Apple, puis ce texte.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel method = MethodChannel(
    'com.icitranscript/global_shortcut',
  );
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  test('keyLabel demande la touche, rend le caractère de la disposition '
      'courante', () async {
    messenger.setMockMethodCallHandler(method, (MethodCall call) async {
      calls.add(call);
      return call.method == 'keyLabel' ? 'Z' : null;
    });

    final String? label = await GlobalShortcutChannel().keyLabel(13);

    expect(label, 'Z');
    expect(calls.single.method, 'keyLabel');
    expect(calls.single.arguments, <String, Object>{'keyCode': 13});
  });

  test('keyLabel sans plugin : null, sans lever', () async {
    expect(await GlobalShortcutChannel().keyLabel(13), isNull);
  });
}
