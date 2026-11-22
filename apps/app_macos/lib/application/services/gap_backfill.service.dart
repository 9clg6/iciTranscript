import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

/// Transcrit un PCM16 mono 16 kHz hors réunion ; morceaux datés depuis le
/// début du PCM.
abstract interface class PcmTranscriber {
  /// Phrases retrouvées dans [pcm], dans l'ordre.
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm);
}

/// Après la réunion, retranscrit chaque repère « transcription
/// interrompue » depuis le WAV de sa source et le remplace par les phrases
/// retrouvées. Le repère reste si rien n'est retrouvé ou en cas d'échec.
/// Jamais pendant un enregistrement ; un second passage ne change rien.
final class GapBackfillService {
  /// Cree une instance de [GapBackfillService].
  GapBackfillService({
    required PcmTranscriber transcriber,
    required TranscriptRepository transcripts,
    required bool Function() isRecording,
  }) : _transcriber = transcriber,
       _transcripts = transcripts,
       _isRecording = isRecording;

  final PcmTranscriber _transcriber;
  final TranscriptRepository _transcripts;
  final bool Function() _isRecording;
  final Log _log = Log.named('GapBackfillService');

  /// Élargissement de l'intervalle de chaque perte (mots coupés aux bords).
  static const Duration margin = Duration(seconds: 1);

  static const int _bytesPerMs = 32; // PCM16 mono 16 kHz
  static const int _wavHeaderBytes = 44;
  static final RegExp _markerTimes = RegExp(
    r'(\d+):(\d{2}):(\d{2})\s*[–-]\s*(\d+):(\d{2}):(\d{2})',
  );

  /// Intervalles à retranscrire : un par repère, élargi de [margin], jamais
  /// avant le début de la réunion.
  static List<({String markerId, AudioSource source, int startMs, int endMs})>
  plan(List<TranscriptSegmentEntity> segments) =>
      <({String markerId, AudioSource source, int startMs, int endMs})>[
        for (final TranscriptSegmentEntity s in segments)
          if (s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
            if (_markerTimes.firstMatch(s.text) case final RegExpMatch m)
              (
                markerId: s.id,
                source: s.source,
                startMs: (s.timestampMs - margin.inMilliseconds).clamp(
                  0,
                  s.timestampMs,
                ),
                endMs: _ms(m, 4) + margin.inMilliseconds,
              ),
      ];

  static int _ms(RegExpMatch m, int first) =>
      ((int.parse(m.group(first)!) * 60 + int.parse(m.group(first + 1)!)) * 60 +
          int.parse(m.group(first + 2)!)) *
      1000;

  /// Retranscrit les repères de [sessionId] depuis
  /// `<recordingsDirectory>/<sessionId>_mic.wav` / `_system.wav`.
  Future<void> backfill(
    String sessionId, {
    required String recordingsDirectory,
  }) async {
    if (_isRecording()) return;
    final List<TranscriptSegmentEntity> segments = await _transcripts
        .getBySessionId(sessionId);
    for (final ({String markerId, AudioSource source, int startMs, int endMs})
        gap
        in plan(segments)) {
      // Le serveur ne tient pas un troisième flux (sonde) : on s'arrête dès
      // qu'un enregistrement commence.
      if (_isRecording()) return;
      final String track = gap.source == AudioSource.input ? 'mic' : 'system';
      final Uint8List? pcm = await _readPcm(
        '$recordingsDirectory/${sessionId}_$track.wav',
        gap.startMs,
        gap.endMs,
      );
      if (pcm == null || pcm.isEmpty) continue;
      final List<({int offsetMs, String text})> pieces;
      try {
        pieces = await _transcriber.transcribe(pcm);
      } catch (e) {
        _log.warning('Rattrapage de ${gap.markerId} échoué, repère gardé: $e');
        continue;
      }
      if (pieces.isEmpty) continue;
      for (int k = 0; k < pieces.length; k++) {
        await _transcripts.save(
          TranscriptSegmentEntity(
            id: '${gap.markerId}_backfill_$k',
            sessionId: sessionId,
            source: gap.source,
            text: pieces[k].text,
            timestampMs: gap.startMs + pieces[k].offsetMs,
            createdAt: clock.now(),
          ),
        );
      }
      await _transcripts.deleteById(gap.markerId);
    }
  }

  Future<Uint8List?> _readPcm(String path, int startMs, int endMs) async {
    final File file = File(path);
    if (!file.existsSync()) return null;
    final RandomAccessFile raf = await file.open();
    try {
      final int start = _wavHeaderBytes + startMs * _bytesPerMs;
      final int end = (_wavHeaderBytes + endMs * _bytesPerMs).clamp(
        start,
        await raf.length(),
      );
      await raf.setPosition(start);
      return await raf.read((end - start) & ~1);
    } finally {
      await raf.close();
    }
  }
}
