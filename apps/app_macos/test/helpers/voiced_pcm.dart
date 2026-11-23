import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';

/// Amplitude de base d'un PCM « parlé » des bancs : au-dessus de la porte
/// de parole du direct (`isSpeechChunk`, seuil de continuation), comme une
/// vraie voix. Les WAV des bancs étaient du silence numérique (un ou deux
/// échantillons non nuls par chunk) qui se faisait passer pour de la
/// parole ; le rattrapage applique désormais la porte avant de ranger.
const int voicedLevel = 1000;

/// PCM16 de [bytes] octets qui passe la porte de parole : signe alterné,
/// chaque échantillon vaut ±([voicedLevel] + [value]). [value] (au plus
/// 31767) se relit à n'importe quel échantillon par [voicedValue], même
/// quand le rattrapage lit à partir d'une heure qui n'est pas alignée.
Uint8List voicedPcm(int bytes, {int value = 0}) {
  final Uint8List out = Uint8List(bytes);
  final ByteData d = ByteData.sublistView(out);
  final int level = voicedLevel + value;
  for (int o = 0; o + 1 < bytes; o += 2) {
    d.setInt16(o, (o ~/ 2).isEven ? level : -level, Endian.little);
  }
  return out;
}

/// Valeur portée par le premier échantillon d'un PCM écrit par [voicedPcm].
int voicedValue(Uint8List pcm) =>
    ByteData.sublistView(pcm).getInt16(0, Endian.little).abs() - voicedLevel;

/// Chunk de 100 ms dont les premiers échantillons valent [head] tels quels
/// (numéro du chunk, lu par les transcripteurs factices) et le reste est
/// parlé.
Uint8List voicedChunk(List<int> head) {
  final Uint8List out = voicedPcm(3200);
  final ByteData d = ByteData.sublistView(out);
  for (int i = 0; i < head.length; i++) {
    d.setInt16(i * 2, head[i], Endian.little);
  }
  return out;
}

/// Garde du banc : [pcm] passe la porte de parole du direct.
bool isVoiced(Uint8List pcm) =>
    TranscriptionRemoteDataSourceImpl.isSpeechChunk(pcm);
