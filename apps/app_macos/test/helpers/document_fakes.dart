import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/file_picker_channel.dart';

/// Canal de l'extraction de texte des PDF (côté Swift : PDFKit).
///
/// Contrat : méthode `extractText`, arguments `{path: String}`, résultat
/// `String` (texte du PDF, éventuellement vide) ; échec = PlatformException.
const MethodChannel kDocumentTextTestChannel = MethodChannel(
  'com.icitranscript/document_text',
);

/// Répond aux appels du canal PDF avec [handler] et garde chaque appel.
List<MethodCall> mockPdfChannel(
  Future<Object?> Function(MethodCall call) handler,
) {
  final List<MethodCall> calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kDocumentTextTestChannel, (MethodCall call) {
        calls.add(call);
        return handler(call);
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kDocumentTextTestChannel, null),
  );
  return calls;
}

/// Dossier temporaire du test, supprimé à la fin.
Directory tempFolder() {
  final Directory dir = Directory.systemTemp.createTempSync('oats_docs_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Écrit [content] dans [dir]/[name] et rend le chemin.
String writeFile(Directory dir, String name, String content) {
  final File file = File('${dir.path}/$name')..writeAsStringSync(content);
  return file.path;
}

/// Sélecteur de fichiers factice : rend [next] (ou lève [error]) et garde
/// les extensions demandées. Aucune fenêtre système.
class FakeFilePicker extends FilePickerChannel {
  FakeFilePicker({this.next = const <String>[]});

  /// Chemins rendus au prochain appel ; vide = l'utilisateur a annulé.
  List<String> next;

  /// Si non nul, levée au prochain appel (canal cassé).
  Object? error;

  /// Extensions demandées, un élément par appel.
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<List<String>> pickFiles({required List<String> extensions}) async {
    calls.add(extensions);
    if (error case final Object e) throw e;
    return next;
  }
}
