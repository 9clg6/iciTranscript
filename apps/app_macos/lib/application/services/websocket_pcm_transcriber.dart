import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';

/// [PcmTranscriber] sur le serveur voxmlx, par une socket dédiée de courte
/// durée, utilisée seulement hors enregistrement. Le PCM part par morceaux
/// de 30 s au plus, un à la fois, comme le renvoi étalé : chaque morceau
/// attend son `done` avant le suivant.
// ponytail: morceaux à taille fixe (une phrase peut être coupée au bord) ;
// couper sur les silences si les bords gênent. URL par défaut du serveur
// local, pas celle de la dernière session.
final class WebSocketPcmTranscriber implements PcmTranscriber {
  /// Cree une instance de [WebSocketPcmTranscriber].
  WebSocketPcmTranscriber({
    this.url = 'ws://localhost:8000/v1/realtime',
    WebSocketClient Function()? createClient,
  }) : _createClient = createClient ?? WebSocketClient.new;

  /// Point d'entrée du serveur de transcription.
  final String url;
  final WebSocketClient Function() _createClient;

  static const int _pieceBytes = 30000 * 32; // 30 s de PCM16 16 kHz
  static const int _chunkBytes = 3200; // 100 ms
  static const Duration _doneTimeout = Duration(seconds: 60);

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final WebSocketClient client = _createClient();
    await client.connect(url);
    try {
      final List<({int offsetMs, String text})> pieces =
          <({int offsetMs, String text})>[];
      for (int start = 0; start < pcm.length; start += _pieceBytes) {
        final int end = (start + _pieceBytes).clamp(0, pcm.length);
        final Future<String> done = client.messageStream
            .map((String m) => jsonDecode(m) as Map<String, dynamic>)
            .firstWhere(
              (Map<String, dynamic> e) =>
                  e['type'] == 'response.audio_transcript.done',
            )
            .then((Map<String, dynamic> e) => e['text'] as String? ?? '')
            .timeout(_doneTimeout);
        for (int c = start; c < end; c += _chunkBytes) {
          client.send(
            jsonEncode(<String, String>{
              'type': 'input_audio_buffer.append',
              'audio': base64Encode(
                Uint8List.sublistView(pcm, c, (c + _chunkBytes).clamp(0, end)),
              ),
            }),
          );
        }
        client.send('{"type":"input_audio_buffer.commit","final":true}');
        final String text = TranscriptTextNormalizer.normalize(await done);
        if (text.isNotEmpty &&
            !TranscriptTextNormalizer.isForeignScript(text)) {
          pieces.add((offsetMs: start ~/ 32, text: text));
        }
      }
      return pieces;
    } finally {
      await client.dispose();
    }
  }
}
