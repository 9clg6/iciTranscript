import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/voiced_pcm.dart';

// Garde des bancs : l'audio « parlé » des WAV de test passe la porte de
// parole du direct, le silence non ; la valeur portée se relit.
void main() {
  test('un PCM parlé passe la porte, et sa valeur se relit', () {
    final Uint8List pcm = voicedPcm(3200, value: 20000);
    expect(isVoiced(pcm), isTrue);
    expect(voicedValue(pcm), 20000);
    expect(voicedValue(Uint8List.sublistView(pcm, 2)), 20000);
  });

  test('un chunk numéroté reste parlé', () {
    expect(isVoiced(voicedChunk(<int>[4242, 1])), isTrue);
  });

  test('le silence numérique (ancien banc : deux échantillons non nuls) ne '
      'passe pas', () {
    final Uint8List old = Uint8List(3200);
    ByteData.sublistView(old)
      ..setInt16(0, 4242, Endian.little)
      ..setInt16(2, 1, Endian.little);
    expect(isVoiced(old), isFalse);
  });
}
