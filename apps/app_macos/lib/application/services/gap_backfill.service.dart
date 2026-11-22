import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

/// Le transcripteur n'a pas atteint le serveur (connexion refusée) ou a
/// cédé la place à un enregistrement : la tentative ne compte pas.
final class TranscriberUnavailable implements Exception {
  /// Cree une instance de [TranscriberUnavailable].
  const TranscriberUnavailable(this.reason);

  /// Pourquoi.
  final String reason;

  @override
  String toString() => 'TranscriberUnavailable: $reason';
}

/// Issue d'un rattrapage : repères restants, et si le serveur a été atteint
/// (sinon la tentative ne compte pas pour la limite de reprises).
typedef BackfillOutcome = ({int markersLeft, bool reachedServer});

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
  ///
  /// Rend les repères restants (WAV présent) et si le serveur a été atteint :
  /// une connexion refusée ou un enregistrement qui commence n'est pas une
  /// tentative ; une réponse sans rien de neuf en est une.
  Future<BackfillOutcome> backfill(
    String sessionId, {
    required String recordingsDirectory,
  }) async {
    final List<TranscriptSegmentEntity> segments = await _transcripts
        .getBySessionId(sessionId);
    final List<({String markerId, AudioSource source, int startMs, int endMs})>
    gaps = plan(segments);
    if (_isRecording()) return (markersLeft: gaps.length, reachedServer: false);
    int left = 0;
    bool reached = false;
    for (int g = 0; g < gaps.length; g++) {
      final ({String markerId, AudioSource source, int startMs, int endMs})
      gap = gaps[g];
      // Le serveur ne tient pas un troisième flux (sonde) : on s'arrête dès
      // qu'un enregistrement commence.
      if (_isRecording()) {
        return (markersLeft: left + gaps.length - g, reachedServer: reached);
      }
      final String track = gap.source == AudioSource.input ? 'mic' : 'system';
      final Uint8List? pcm = await _readPcm(
        '$recordingsDirectory/${sessionId}_$track.wav',
        gap.startMs,
        gap.endMs,
      );
      if (pcm == null || pcm.isEmpty) continue;
      List<({int offsetMs, String text})> pieces;
      try {
        pieces = await _transcriber.transcribe(pcm);
      } on TranscriberUnavailable catch (e) {
        _log.info('Rattrapage de ${gap.markerId} reporté: $e');
        left++;
        continue;
      } on SocketException catch (e) {
        _log.info('Rattrapage de ${gap.markerId} reporté (serveur absent): $e');
        left++;
        continue;
      } catch (e) {
        _log.warning('Rattrapage de ${gap.markerId} échoué, repère gardé: $e');
        reached = true;
        left++;
        continue;
      }
      reached = true;
      final TranscriptSegmentEntity marker = segments.firstWhere(
        (TranscriptSegmentEntity s) => s.id == gap.markerId,
      );
      final List<({int offsetMs, String text})> kept = trimOverlaps(
        pieces,
        before: _neighbour(segments, marker, before: true)?.text,
        after: _neighbour(segments, marker, before: false)?.text,
      );
      // Tout ce qui a été retrouvé était déjà dans les voisins : rien de
      // nouveau, le repère reste (jamais de texte en double).
      if (kept.isEmpty) {
        left++;
        continue;
      }
      pieces = kept;
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
    return (markersLeft: left, reachedServer: reached);
  }

  /// Segment en direct (non repère) de la même source juste avant ou juste
  /// après [marker].
  static TranscriptSegmentEntity? _neighbour(
    List<TranscriptSegmentEntity> segments,
    TranscriptSegmentEntity marker, {
    required bool before,
  }) {
    TranscriptSegmentEntity? best;
    for (final TranscriptSegmentEntity s in segments) {
      if (s.id == marker.id ||
          s.source != marker.source ||
          s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix)) {
        continue;
      }
      if (before
          ? s.timestampMs <= marker.timestampMs &&
                (best == null || s.timestampMs > best.timestampMs)
          : s.timestampMs > marker.timestampMs &&
                (best == null || s.timestampMs < best.timestampMs)) {
        best = s;
      }
    }
    return best;
  }

  // Au moins deux mots communs, sauf si tout le morceau est répété : un
  // seul mot (« le », « the ») se répète trop souvent par hasard pour être
  // retiré sans risque de perdre un mot.
  static const int _minOverlapWords = 2;

  /// Retire des morceaux retrouvés les mots déjà présents dans les segments
  /// voisins : la fin de [before] en tête du premier morceau, le début de
  /// [after] en queue du dernier (la marge les retranscrit). Mots entiers,
  /// sans casse ni ponctuation ; un morceau vidé est écarté ; les heures ne
  /// changent pas.
  static List<({int offsetMs, String text})> trimOverlaps(
    List<({int offsetMs, String text})> pieces, {
    String? before,
    String? after,
  }) {
    if (pieces.isEmpty) return pieces;
    final List<List<String>> words = <List<String>>[
      for (final ({int offsetMs, String text}) p in pieces) _words(p.text),
    ];
    if (before != null) {
      words.first = _dropOverlap(
        words.first,
        _keys(_words(before)),
        atEnd: false,
      );
    }
    if (after != null) {
      words.last = _dropOverlap(words.last, _keys(_words(after)), atEnd: true);
    }
    return <({int offsetMs, String text})>[
      for (int i = 0; i < pieces.length; i++)
        if (_keys(words[i]).isNotEmpty)
          (offsetMs: pieces[i].offsetMs, text: words[i].join(' ')),
    ];
  }

  static List<String> _words(String text) =>
      text.trim().split(RegExp(r'\s+'))..removeWhere((String w) => w.isEmpty);

  static String _key(String word) => word.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static List<String> _keys(List<String> words) => <String>[
    for (final String w in words)
      if (_key(w).isNotEmpty) _key(w),
  ];

  /// [piece] sans son plus long recouvrement avec [neighbour] : la fin de
  /// [neighbour] contre le début de [piece], ou le début de [neighbour]
  /// contre la fin de [piece] si [atEnd]. Les signes seuls laissés au bord
  /// partent avec.
  static List<String> _dropOverlap(
    List<String> piece,
    List<String> neighbour, {
    required bool atEnd,
  }) {
    // Indices des mots (signes seuls exclus) de [piece].
    final List<int> at = <int>[
      for (int i = 0; i < piece.length; i++)
        if (_key(piece[i]).isNotEmpty) i,
    ];
    final List<String> keys = <String>[for (final int i in at) _key(piece[i])];
    for (
      int k = keys.length < neighbour.length ? keys.length : neighbour.length;
      k >= 1;
      k--
    ) {
      final List<String> mine = atEnd
          ? keys.sublist(keys.length - k)
          : keys.sublist(0, k);
      final List<String> theirs = atEnd
          ? neighbour.sublist(0, k)
          : neighbour.sublist(neighbour.length - k);
      if (!_sameWords(mine, theirs)) continue;
      if (k < _minOverlapWords && k < keys.length) continue;
      if (atEnd) {
        final List<String> rest = piece.sublist(0, at[keys.length - k]);
        while (rest.isNotEmpty && _key(rest.last).isEmpty) {
          rest.removeLast();
        }
        return rest;
      }
      final List<String> rest = piece.sublist(at[k - 1] + 1);
      while (rest.isNotEmpty && _key(rest.first).isEmpty) {
        rest.removeAt(0);
      }
      return rest;
    }
    return piece;
  }

  static bool _sameWords(List<String> a, List<String> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
