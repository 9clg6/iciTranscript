import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/file_picker_channel.dart';

/// Côté Dart du sélecteur de fichiers (besoin A5), contrat pour
/// l'implémentation Swift (NSOpenPanel) :
/// canal `com.icitranscript/file_picker`, méthode `pickFiles`, arguments
/// `{extensions: List<String>}` (sans point, minuscules), résultat
/// `List<String>` de chemins absolus, ou null si l'utilisateur annule.
///
/// API supposée (lib/core/platform/file_picker_channel.dart) :
/// `class FilePickerChannel` (constructeur `const FilePickerChannel()`),
/// méthode `pickFiles({required List<String> extensions})` qui rend un
/// `Future<List<String>>`,
/// et `filePickerProvider` (lib/core/providers/platform/file_picker.provider.dart)
/// qui le fournit (remplacé par un faux dans les tests d'écran).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.icitranscript/file_picker');

  List<MethodCall> answer(Object? result) {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return result;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    return calls;
  }

  test('pickFiles {extensions} rend les chemins choisis', () async {
    final List<MethodCall> calls = answer(<Object?>[
      '/Users/me/Documents/plan.md',
      '/Users/me/Documents/rapport.pdf',
    ]);

    final List<String> paths = await const FilePickerChannel().pickFiles(
      extensions: <String>['txt', 'md', 'pdf'],
    );

    expect(paths, <String>[
      '/Users/me/Documents/plan.md',
      '/Users/me/Documents/rapport.pdf',
    ]);
    expect(calls.single.method, 'pickFiles');
    expect(calls.single.arguments, <String, Object?>{
      'extensions': <String>['txt', 'md', 'pdf'],
    });
  });

  test('annulation (null) : liste vide, pas d\'erreur', () async {
    answer(null);

    expect(
      await const FilePickerChannel().pickFiles(extensions: <String>['md']),
      isEmpty,
    );
  });
}
