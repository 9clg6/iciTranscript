import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

/// [PcmTranscriber] sur le serveur voxmlx, par une socket dédiée de courte
/// durée, utilisée seulement hors enregistrement. Le PCM part par morceaux
/// de 30 s au plus, un à la fois, comme le renvoi étalé : chaque morceau
/// attend son `done` avant le suivant.
// ponytail: morceaux à taille fixe (une phrase peut être coupée au bord) ;
// couper sur les silences si les bords gênent. L'URL vient des ports
// résolus pour ce lancement (ServerPorts), comme la transcription en direct.
final class WebSocketPcmTranscriber implements PcmTranscriber {
  /// Cree une instance de [WebSocketPcmTranscriber].
  WebSocketPcmTranscriber({
    String? url,
    WebSocketClient Function()? createClient,
    bool Function()? shouldYield,
  }) : url = url ?? serverPorts().transcriptionWebSocket.toString(),
       _createClient = createClient ?? WebSocketClient.new,
       _shouldYield = shouldYield ?? _never;

  static bool _never() => false;

  /// Lu avant la connexion et avant chaque morceau : vrai (un enregistrement
  /// démarre) → la retranscription s'arrête, socket fermée, sans compter.
  final bool Function() _shouldYield;

  /// Point d'entrée du serveur de transcription (ports de ce lancement).
  final String url;
  final WebSocketClient Function() _createClient;

  // Poignées de main expirées de suite : allongent la suivante, comme la
  // reconnexion en direct (sonde 13 : serveur occupé par l'arriéré de la
  // réunion, accepte en 15–30 s).
  int _slowAccepts = 0;

  /// Durée maximale d'un morceau : un démarrage n'attend qu'environ un
  /// morceau sur le serveur séquentiel (sonde 4 : 8,8 s avec 30 s).
  static const Duration maxPiece = Duration(seconds: 12);
  static const int _chunkBytes = 3200; // 100 ms, le pas de la porte RMS
  static const Duration _doneTimeout = Duration(seconds: 60);

  static const Duration _yieldPoll = Duration(milliseconds: 100);

  /// Morceaux (octets) de [maxPiece] au plus, coupés à la fin du plus long
  /// silence de la fenêtre (porte RMS par pas de 100 ms ; à égalité, le
  /// plus tardif) : une phrase plus courte que la borne n'est jamais
  /// coupée ; une parole continue plus longue l'est à la borne.
  static List<({int start, int end})> splitAtSilences(Uint8List pcm) {
    final int chunks = (pcm.length + _chunkBytes - 1) ~/ _chunkBytes;
    final List<bool> speech = <bool>[
      for (int c = 0; c < chunks; c++)
        TranscriptionRemoteDataSourceImpl.isSpeechChunk(
          Uint8List.sublistView(
            pcm,
            c * _chunkBytes,
            ((c + 1) * _chunkBytes).clamp(0, pcm.length),
          ),
        ),
    ];
    final int maxChunks = maxPiece.inMilliseconds ~/ 100;
    final List<({int start, int end})> pieces = <({int start, int end})>[];
    int start = 0;
    while (start < chunks) {
      int end = start + maxChunks;
      if (end >= chunks) {
        end = chunks;
      } else {
        // Coupe dans le plus long silence de la fenêtre (à égalité, le plus
        // tardif) : une pause entre phrases, pas une virgule (sonde 5 :
        // couper au dernier silence tombait 3 fois sur 9 à la virgule). Au
        // milieu du silence : une phrase commence parfois un pas avant son
        // énergie mesurable. Un silence qui ouvre le morceau est coupé à sa
        // fin. Sans silence, la borne.
        final int windowEnd = end;
        int bestLength = 0;
        int run = 0;
        for (int c = start; c < windowEnd; c++) {
          run = speech[c] ? 0 : run + 1;
          final bool runEnds = c + 1 == windowEnd || speech[c + 1];
          if (run == 0 || !runEnds || run < bestLength) continue;
          final int runStart = c + 1 - run;
          final int cut = runStart == start ? c + 1 : (runStart + c + 1) ~/ 2;
          if (cut <= start) continue;
          bestLength = run;
          end = cut;
        }
        if (bestLength == 0) end = windowEnd;
      }
      pieces.add((
        start: start * _chunkBytes,
        end: (end * _chunkBytes).clamp(0, pcm.length),
      ));
      start = end;
    }
    return pieces;
  }

  /// [done], ou [TranscriberUnavailable] dès qu'un enregistrement démarre :
  /// la socket se ferme sans attendre la fin du morceau en vol.
  Future<String> _unlessYield(Future<String> done) {
    final Completer<String> result = Completer<String>();
    final Timer poll = Timer.periodic(_yieldPoll, (_) {
      if (_shouldYield() && !result.isCompleted) {
        result.completeError(const TranscriberUnavailable('enregistrement'));
      }
    });
    done.then(
      (String text) {
        if (!result.isCompleted) result.complete(text);
      },
      onError: (Object e, StackTrace st) {
        if (!result.isCompleted) result.completeError(e, st);
      },
    );
    return result.future.whenComplete(poll.cancel);
  }

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    if (_shouldYield()) throw const TranscriberUnavailable('enregistrement');
    final WebSocketClient client = _createClient()
      ..handshakeTimeout = WebSocketClient.handshakeBound(_slowAccepts);
    final DateTime asked = clock.now();
    try {
      await client.connect(url);
    } on TimeoutException catch (e) {
      _slowAccepts++;
      await client.dispose();
      throw TranscriberUnavailable('connexion refusée ($e)');
    } on Exception catch (e) {
      await client.dispose();
      throw TranscriberUnavailable('connexion refusée ($e)');
    }
    // Un serveur qui a accepté lentement l'est encore : la borne reste.
    if (clock.now().difference(asked) <= WebSocketClient.connectTimeout) {
      _slowAccepts = 0;
    }
    try {
      final List<({int offsetMs, String text})> pieces =
          <({int offsetMs, String text})>[];
      for (final ({int start, int end}) piece in splitAtSilences(pcm)) {
        if (_shouldYield()) {
          throw const TranscriberUnavailable('enregistrement');
        }
        final int start = piece.start;
        final int end = piece.end;
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
        final String text = TranscriptTextNormalizer.normalize(
          await _unlessYield(done),
        );
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
