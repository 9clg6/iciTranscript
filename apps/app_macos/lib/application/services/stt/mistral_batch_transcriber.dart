import 'dart:typed_data';

import 'package:core_foundation/logging/logger.dart';
import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';

/// Rattrapage et dictée par l'API Mistral « batch » (moteur en ligne) : le
/// PCM est envoyé en WAV 16 kHz mono, les segments horodatés reviennent en
/// morceaux. Ce qui est rendu passe ensuite par les portes habituelles du
/// rattrapage (porte de parole, doublons, repère qui rétrécit).
final class MistralBatchTranscriber implements BilledPcmTranscriber {
  /// Cree une instance de [MistralBatchTranscriber]. [apiKey] est lue à
  /// chaque appel (trousseau) ; jamais journalisée.
  MistralBatchTranscriber({
    required Dio dio,
    required Future<String?> Function() apiKey,
  }) : _dio = dio,
       _apiKey = apiKey;

  /// Modèle batch (sonde réelle : 60 s rendues en 3,3 s, segments).
  static const String model = 'voxtral-mini-transcribe-3-0';

  /// Adresse de l'API.
  static const String endpoint =
      'https://api.mistral.ai/v1/audio/transcriptions';

  final Dio _dio;
  final Future<String?> Function() _apiKey;
  final Log _log = Log.named('MistralBatchTranscriber');

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      (await transcribeBilled(pcm)).pieces;

  /// Audio facturé : `usage.prompt_audio_seconds` de la réponse (peut être
  /// fractionnaire), sinon la longueur du PCM.
  @override
  Future<({List<({int offsetMs, String text})> pieces, int billedMs})>
  transcribeBilled(Uint8List pcm) async {
    final String? key = await _apiKey();
    if (key == null || key.isEmpty) {
      throw const TranscriberUnavailable('pas de clé Mistral');
    }
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        endpoint,
        data: FormData.fromMap(<String, Object>{
          'model': model,
          // Incompatible avec `language` : la langue est détectée.
          'timestamp_granularities': 'segment',
          'file': MultipartFile.fromBytes(_wav(pcm), filename: 'audio.wav'),
        }),
        options: Options(
          headers: <String, String>{'Authorization': 'Bearer $key'},
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      // Le message d'une erreur peut recopier les en-têtes (la clé) : seul
      // le code est journalisé.
      final int? status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        _log.warning('Mistral : clé refusée ($status)');
        throw const TranscriberUnavailable('clé refusée');
      }
      _log.warning('Mistral injoignable (${status ?? e.type.name})');
      throw TranscriberUnavailable('serveur injoignable (${status ?? 0})');
    }
    final Object? body = response.data;
    final Object? segments = body is Map<String, dynamic>
        ? body['segments']
        : null;
    final Object? usage = body is Map<String, dynamic> ? body['usage'] : null;
    final Object? seconds = usage is Map<String, dynamic>
        ? usage['prompt_audio_seconds']
        : null;
    final int billedMs = seconds is num
        ? (seconds * 1000).round()
        : pcm.length ~/ 32;
    if (segments is! List<dynamic>) {
      return (
        pieces: const <({int offsetMs, String text})>[],
        billedMs: billedMs,
      );
    }
    final List<({int offsetMs, String text})> pieces =
        <({int offsetMs, String text})>[
          for (final Object? s in segments)
            if (s is Map<String, dynamic> &&
                s['start'] is num &&
                (s['text'] as String? ?? '').trim().isNotEmpty)
              (
                offsetMs: ((s['start'] as num) * 1000).round(),
                text: (s['text'] as String).trim(),
              ),
        ];
    return (pieces: pieces, billedMs: billedMs);
  }

  /// [pcm] (PCM16 mono 16 kHz) dans un fichier WAV.
  static Uint8List _wav(Uint8List pcm) {
    final ByteData h = ByteData(44);
    void str(int at, String s) {
      for (int i = 0; i < s.length; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, 16000, Endian.little)
      ..setUint32(28, 32000, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return Uint8List(44 + pcm.length)
      ..setRange(0, 44, h.buffer.asUint8List())
      ..setRange(44, 44 + pcm.length, pcm);
  }
}
