import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';

/// Côté Dart de la sortie de la dictée (T2). Contrat du plugin Swift :
///
/// MethodChannel `com.icitranscript/text_output`
/// - `isAccessibilityTrusted` → bool, sans afficher la demande système.
/// - `copy` {text: String} : remplace le presse-papiers par ce texte.
/// - `saveClipboard` : garde côté Swift une copie opaque de TOUS les
///   éléments du presse-papiers (image, fichiers…), pas seulement du texte.
/// - `restoreClipboard` : remet cette copie.
/// - `paste` : ⌘V synthétique vers l'app au premier plan ; lève une
///   PlatformException en cas d'échec.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel method = MethodChannel('com.icitranscript/text_output');
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

  test('permission Accessibilité : vrai ou faux selon Swift', () async {
    answer((_) => true);
    expect(await TextOutputChannel().isAccessibilityTrusted(), isTrue);
    answer((_) => false);
    expect(await TextOutputChannel().isAccessibilityTrusted(), isFalse);
    expect(calls.map((MethodCall c) => c.method).toSet(), <String>{
      'isAccessibilityTrusted',
    });
  });

  test('permission inconnue (réponse nulle ou plugin absent) : faux', () async {
    answer((_) => null);
    expect(await TextOutputChannel().isAccessibilityTrusted(), isFalse);
    messenger.setMockMethodCallHandler(method, null);
    expect(await TextOutputChannel().isAccessibilityTrusted(), isFalse);
  });

  test('copy envoie le texte', () async {
    answer((_) => null);

    await TextOutputChannel().copy('Bonjour à tous');

    expect(calls.single.method, 'copy');
    expect(calls.single.arguments, <String, Object>{'text': 'Bonjour à tous'});
  });

  test('sauvegarde, collage et restauration : une méthode chacun', () async {
    answer((_) => null);
    final TextOutputChannel channel = TextOutputChannel();

    await channel.saveClipboard();
    await channel.paste();
    await channel.restoreClipboard();

    expect(calls.map((MethodCall c) => c.method).toList(), <String>[
      'saveClipboard',
      'paste',
      'restoreClipboard',
    ]);
  });

  test('collage refusé par Swift : l erreur remonte (le texte reste alors '
      'sur le presse-papiers)', () async {
    answer((_) => throw PlatformException(code: 'PASTE_FAILED'));

    await expectLater(
      TextOutputChannel().paste(),
      throwsA(isA<PlatformException>()),
    );
  });
}
