import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:clock/clock.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
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

/// Intervalle à retranscrire pour un repère (un morceau si une dictée le
/// coupe), et segments que le texte retrouvé remplace.
typedef BackfillGap = ({
  String markerId,
  AudioSource source,
  int startMs,
  int endMs,
  List<String> replacedIds,
});

/// Issue d'un rattrapage : repères restants, et si le serveur a été atteint
/// (sinon la tentative ne compte pas pour la limite de reprises).
typedef BackfillOutcome = ({
  int markersLeft,
  bool reachedServer,
  bool progressed,
});

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
    DictatedIntervalsStore? dictatedIntervals,
  }) : _transcriber = transcriber,
       _transcripts = transcripts,
       _isRecording = isRecording,
       _dictated = dictatedIntervals;

  final PcmTranscriber _transcriber;
  final TranscriptRepository _transcripts;
  final bool Function() _isRecording;
  final DictatedIntervalsStore? _dictated;
  // Phrases du bord de fin reconnues intactes pendant ce rattrapage.
  final Set<String> _intactEdges = <String>{};
  final Log _log = Log.named('GapBackfillService');

  /// Élargissement de l'intervalle de chaque perte (mots coupés aux bords).
  static const Duration margin = Duration(seconds: 1);

  static const int _bytesPerMs = 32; // PCM16 mono 16 kHz
  static const int _wavHeaderBytes = 44;
  static final RegExp _markerTimes = RegExp(
    r'(\d+):(\d{2}):(\d{2})\s*[–-]\s*(\d+):(\d{2}):(\d{2})',
  );

  /// Intervalles à retranscrire : un par repère, élargi de [margin], jamais
  /// avant le début de la réunion. Les repères micro sont coupés autour des
  /// intervalles [dictated] (jamais la dictée dans la note) : un repère peut
  /// donner plusieurs morceaux, ou aucun. Un repère tout entier dans une
  /// dictée n'en donne aucun ([dictatedMarkers]).
  ///
  /// Bords, PAR LE TEMPS (sonde 5) : tout segment de la source dont le
  /// début tombe dans [début − [edgeTolerance], fin + [edgeTolerance]] est
  /// remplacé par le texte retrouvé ([BackfillGap.replacedIds]), quel que
  /// soit son texte : phrase coupée avant la perte, partielle sauvée dedans,
  /// abîmée au bord de fin. L'intervalle s'étend pour couvrir ces phrases
  /// (jusqu'au segment intact suivant, 30 s au plus). Les autres sources,
  /// les segments hors fenêtre et les passages non transcrits ne sont
  /// jamais touchés.
  ///
  /// Les repères rangés d'une source qui se recoupent ou se touchent (un
  /// repère provisoire et un final après un arrêt brutal, sonde 7) forment
  /// une union : un seul intervalle, sous le premier repère ; les autres
  /// repères de l'union sont dans [BackfillGap.replacedIds] et partent quand
  /// l'union est retrouvée.
  static List<BackfillGap> plan(
    List<TranscriptSegmentEntity> segments, {
    List<DictatedInterval> dictated = const <DictatedInterval>[],
  }) {
    final List<BackfillGap> gaps = <BackfillGap>[];
    // Fin planifiée de l'union précédente, par source : le recul du début
    // s'y arrête (jamais deux fois le même audio).
    final Map<AudioSource, int> planned = <AudioSource, int>{};
    for (final _MarkerUnion u in _unions(segments, dictated)) {
      for (final BackfillGap g in _planMarker(
        u.first,
        u.end,
        segments,
        dictated,
        endLimit: u.nextStart,
        startLimit: planned[u.first.source],
      )) {
        gaps.add((
          markerId: g.markerId,
          source: g.source,
          startMs: g.startMs,
          endMs: g.endMs,
          replacedIds: <String>[...g.replacedIds, ...u.others],
        ));
        planned[g.source] = g.endMs;
      }
    }
    return gaps;
  }

  /// Unions des repères de perte d'une même source (début, fin), hors
  /// dictée, triées par début.
  static List<_MarkerUnion> _unions(
    List<TranscriptSegmentEntity> segments,
    List<DictatedInterval> dictated,
  ) {
    final List<({TranscriptSegmentEntity marker, int end})> markers =
        <({TranscriptSegmentEntity marker, int end})>[
          for (final TranscriptSegmentEntity s in segments)
            if (_isGapMarker(s))
              if (_markerTimes.firstMatch(s.text) case final RegExpMatch m)
                if (!_insideDictation(s, m, dictated))
                  (marker: s, end: _ms(m, 4)),
        ]..sort(
          (
            ({TranscriptSegmentEntity marker, int end}) a,
            ({TranscriptSegmentEntity marker, int end}) b,
          ) => a.marker.timestampMs.compareTo(b.marker.timestampMs),
        );
    final List<_MarkerUnion> unions = <_MarkerUnion>[];
    for (final ({TranscriptSegmentEntity marker, int end}) m in markers) {
      _MarkerUnion? open;
      for (final _MarkerUnion u in unions.reversed) {
        if (u.first.source == m.marker.source &&
            m.marker.timestampMs <= u.end) {
          open = u;
          break;
        }
      }
      if (open == null) {
        unions.add(_MarkerUnion(m.marker, m.end));
      } else {
        open.others.add(m.marker.id);
        if (m.end > open.end) open.end = m.end;
      }
    }
    for (int i = 0; i < unions.length; i++) {
      for (int j = i + 1; j < unions.length; j++) {
        if (unions[j].first.source == unions[i].first.source) {
          unions[i].nextStart = unions[j].first.timestampMs;
          break;
        }
      }
    }
    return unions;
  }

  /// Un segment qui commence à moins de [edgeTolerance] d'un bord de la
  /// perte appartient à la phrase coupée (le texte arrive ~1 s après
  /// l'audio ; sonde 5 : au plus 1,2 s après le début, 1 s avant la fin).
  static const Duration edgeTolerance = Duration(seconds: 2);

  // Au plus, après la dernière phrase remplacée, sans segment intact après.
  static const Duration _afterReplacedSpan = Duration(seconds: 30);

  static bool _isGapMarker(TranscriptSegmentEntity s) =>
      s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

  static bool _isMarker(TranscriptSegmentEntity s) =>
      _isGapMarker(s) || LiveTranscriptionService.isUntranscribedMarker(s.text);

  static List<BackfillGap> _planMarker(
    TranscriptSegmentEntity marker,
    int lostEnd,
    List<TranscriptSegmentEntity> segments,
    List<DictatedInterval> dictated, {
    int? endLimit,
    int? startLimit,
  }) {
    final int tolerance = edgeTolerance.inMilliseconds;
    final List<TranscriptSegmentEntity> live =
        segments
            .where(
              (TranscriptSegmentEntity x) =>
                  x.source == marker.source && !_isMarker(x),
            )
            .toList()
          ..sort(
            (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
                a.timestampMs.compareTo(b.timestampMs),
          );
    final List<TranscriptSegmentEntity> replaced = <TranscriptSegmentEntity>[
      for (final TranscriptSegmentEntity x in live)
        if (x.timestampMs >= marker.timestampMs - tolerance &&
            x.timestampMs <= lostEnd + tolerance)
          x,
    ];
    int start = marker.timestampMs - margin.inMilliseconds;
    int end = lostEnd + margin.inMilliseconds;
    if (replaced.isNotEmpty) {
      if (replaced.first.timestampMs < start) {
        start = replaced.first.timestampMs;
      }
      // Symétrique de la fin : un segment remplacé peut porter l'heure d'une
      // phrase plus récente que son audio (sonde 8). On retranscrit depuis
      // le dernier segment intact avant lui (au plus 30 s) ; trimOverlaps
      // retire la fin de ce voisin : rien n'est supprimé sans être rendu.
      // ponytail: départ [edgeTolerance] après le début du voisin (son texte
      // arrive ~1 s après son audio) pour ne pas le retranscrire en entier ;
      // un texte du voisin un peu différent resterait sinon en double.
      final int first = replaced.first.timestampMs;
      final TranscriptSegmentEntity? previous = live
          .where((TranscriptSegmentEntity x) => x.timestampMs < first)
          .lastOrNull;
      final int back =
          previous != null &&
              first - previous.timestampMs < _afterReplacedSpan.inMilliseconds
          ? math.min(first, previous.timestampMs + tolerance)
          : first - _afterReplacedSpan.inMilliseconds;
      if (back < start) start = back;
      final int last = replaced.last.timestampMs;
      final TranscriptSegmentEntity? next = live
          .where((TranscriptSegmentEntity x) => x.timestampMs > last)
          .firstOrNull;
      final int cover =
          next != null &&
              next.timestampMs - last < _afterReplacedSpan.inMilliseconds
          ? next.timestampMs
          : last + _afterReplacedSpan.inMilliseconds;
      if (cover > end) end = cover;
    }
    // Le recul ne passe pas la fin de l'union précédente (la marge, si).
    if (startLimit != null && start < startLimit) {
      start = math.min(startLimit, marker.timestampMs - margin.inMilliseconds);
    }
    // Le prolongement s'arrête où commence l'union suivante de la source :
    // son audio est retranscrit par elle (jamais deux fois).
    if (endLimit != null && end > endLimit) {
      end = endLimit > lostEnd ? endLimit : lostEnd;
    }
    if (start < 0) start = 0;
    final List<String> ids = <String>[
      for (final TranscriptSegmentEntity x in replaced) x.id,
    ];
    return <BackfillGap>[
      for (final (int from, int to) in subtractIntervals(
        start,
        end,
        marker.source == AudioSource.input
            ? dictated
            : const <DictatedInterval>[],
      ))
        (
          markerId: marker.id,
          source: marker.source,
          startMs: from,
          endMs: to,
          replacedIds: ids,
        ),
    ];
  }

  /// Repères micro dont la perte tient tout entière dans une dictée : la
  /// réunion n'y a rien perdu (ces mots n'allaient pas à la note).
  static List<String> dictatedMarkers(
    List<TranscriptSegmentEntity> segments,
    List<DictatedInterval> dictated,
  ) => <String>[
    for (final TranscriptSegmentEntity s in segments)
      if (s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
        if (_markerTimes.firstMatch(s.text) case final RegExpMatch m)
          if (_insideDictation(s, m, dictated)) s.id,
  ];

  static bool _insideDictation(
    TranscriptSegmentEntity marker,
    RegExpMatch times,
    List<DictatedInterval> dictated,
  ) =>
      marker.source == AudioSource.input &&
      dictated.any(
        (DictatedInterval d) =>
            d.startMs <= marker.timestampMs && _ms(times, 4) <= d.endMs,
      );

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
    _intactEdges.clear();
    _progressed = false;
    _lastRecovered.clear();
    final List<TranscriptSegmentEntity> segments = await _transcripts
        .getBySessionId(sessionId);
    final List<DictatedInterval> dictated =
        _dictated?.read(sessionId) ?? const <DictatedInterval>[];
    // Sans serveur : rien à retranscrire, le repère quitte la note.
    for (final String id in dictatedMarkers(segments, dictated)) {
      await _transcripts.deleteById(id);
    }
    final List<BackfillGap> gaps = plan(segments, dictated: dictated);
    if (_isRecording()) {
      return (
        markersLeft: _markers(gaps, 0),
        reachedServer: false,
        progressed: false,
      );
    }
    int left = 0;
    bool reached = false;
    // Un repère coupé par une dictée a plusieurs morceaux, à la suite : son
    // sort se décide après le dernier.
    final List<_Part> parts = <_Part>[];
    for (int g = 0; g < gaps.length; g++) {
      final BackfillGap gap = gaps[g];
      // Le serveur ne tient pas un troisième flux (sonde) : on s'arrête dès
      // qu'un enregistrement (ou une dictée) commence.
      if (_isRecording()) {
        return (
          markersLeft: left + _markers(gaps, g),
          reachedServer: reached,
          progressed: _progressed,
        );
      }
      final _Part part = await _backfillPart(
        sessionId,
        gap,
        parts.length,
        segments,
        recordingsDirectory,
      );
      parts.add(part);
      if (part != _Part.noAudio && part != _Part.unavailable) reached = true;
      if (part == _Part.cut) {
        // Coupée après avoir avancé : le reste attend la tentative suivante.
        return (
          markersLeft: left + _markers(gaps, g),
          reachedServer: reached,
          progressed: true,
        );
      }
      final bool lastPart =
          g == gaps.length - 1 || gaps[g + 1].markerId != gap.markerId;
      if (!lastPart) continue;
      if (parts.contains(_Part.unavailable) || parts.contains(_Part.failed)) {
        left++;
      } else if (parts.contains(_Part.saved)) {
        await _transcripts.deleteById(gap.markerId);
        for (final String id in gap.replacedIds) {
          if (!_intactEdges.contains(id)) await _transcripts.deleteById(id);
        }
      } else if (parts.contains(_Part.nothingNew)) {
        // Tout ce qui a été retrouvé était déjà dans les voisins : rien de
        // nouveau, le repère reste (jamais de texte en double).
        left++;
      }
      parts.clear();
    }
    return (markersLeft: left, reachedServer: reached, progressed: _progressed);
  }

  // Une tranche au moins rendue pendant cette tentative.
  bool _progressed = false;

  // Dernier morceau rendu par source pendant cette tentative.
  final Map<AudioSource, TranscriptSegmentEntity> _lastRecovered =
      <AudioSource, TranscriptSegmentEntity>{};

  /// Repères distincts de [gaps] à partir de l'indice [from].
  static int _markers(List<BackfillGap> gaps, int from) =>
      gaps.skip(from).map((BackfillGap g) => g.markerId).toSet().length;

  /// Retranscrit un morceau [part] du repère de [gap] et sauve ce qui est
  /// neuf, tranche par tranche ([slice]) : chaque tranche rendue est rangée,
  /// les segments qu'elle remplace partent et le repère rétrécit à ce qui
  /// reste. Une tentative coupée reprend donc là où elle s'est arrêtée. Le
  /// repère n'est retiré qu'à la fin, par [backfill].
  Future<_Part> _backfillPart(
    String sessionId,
    BackfillGap gap,
    int part,
    List<TranscriptSegmentEntity> segments,
    String recordingsDirectory,
  ) async {
    final String track = gap.source == AudioSource.input ? 'mic' : 'system';
    final String path = '$recordingsDirectory/${sessionId}_$track.wav';
    TranscriptSegmentEntity marker = segments.firstWhere(
      (TranscriptSegmentEntity s) => s.id == gap.markerId,
    );
    // On coupe contre les voisins intacts, pas contre les phrases que ce
    // texte remplace.
    final List<TranscriptSegmentEntity> intact = segments
        .where((TranscriptSegmentEntity s) => !gap.replacedIds.contains(s.id))
        .toList();
    final TranscriptSegmentEntity? left = _neighbour(
      intact,
      marker,
      before: true,
    );
    String? before = left?.text;
    // L'union d'avant, rendue juste avant, est le vrai voisin : leurs marges
    // se recoupent, une phrase à la jonction ne doit pas revenir deux fois.
    final TranscriptSegmentEntity? recovered = _lastRecovered[gap.source];
    if (recovered != null &&
        recovered.timestampMs <= gap.endMs &&
        (left == null || recovered.timestampMs >= left.timestampMs)) {
      before = recovered.text;
    }
    final String? after = _neighbour(intact, marker, before: false)?.text;
    // Exception : une phrase qui commence à la fin de la perte ou après, et
    // dont le début se retrouve tel quel dans le texte rattrapé, est intacte
    // (gap_backfill_overlap_test) : on la garde et on retire le doublon.
    // Tout ce qui commence avant la fin reste remplacé, quel que soit son
    // texte (sonde 5).
    // Fin de l'union : celle du plus tardif de ses repères.
    final int? lostEnd = <int>[
      for (final TranscriptSegmentEntity s in segments)
        if ((s.id == marker.id || gap.replacedIds.contains(s.id)) &&
            _isGapMarker(s))
          if (_markerTimes.firstMatch(s.text) case final RegExpMatch m)
            _ms(m, 4),
    ].fold<int?>(null, (int? a, int b) => a == null || b > a ? b : a);
    final TranscriptSegmentEntity? edge = lostEnd == null
        ? null
        : (segments
                  .where(
                    (TranscriptSegmentEntity s) =>
                        gap.replacedIds.contains(s.id) &&
                        s.timestampMs >= lostEnd,
                  )
                  .toList()
                ..sort(
                  (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
                      a.timestampMs.compareTo(b.timestampMs),
                ))
              .firstOrNull;
    final String prefix = part == 0
        ? '${gap.markerId}_backfill_'
        : '${gap.markerId}_backfill_p${part}_';
    _Part result = _Part.noAudio;
    int from = gap.startMs;
    while (from < gap.endMs) {
      // Pas de reste trop court : une coupe juste avant laisserait un bout
      // de repère sans parole, jamais rattrapé.
      int until = from + slice.inMilliseconds;
      if (gap.endMs - until < _minTail.inMilliseconds) until = gap.endMs;
      final Uint8List? read = await _readPcm(path, from, until);
      if (read == null || read.isEmpty) break;
      final Uint8List pcm = until < gap.endMs ? _cutAtSilence(read) : read;
      final int to = from + pcm.length ~/ 32;
      final bool first = from == gap.startMs;
      final bool last = to >= gap.endMs;
      List<({int offsetMs, String text})> pieces;
      try {
        pieces = await _transcriber.transcribe(pcm);
      } on TranscriberUnavailable catch (e) {
        _log.info('Rattrapage de ${gap.markerId} reporté: $e');
        return result == _Part.saved ? _Part.cut : _Part.unavailable;
      } on SocketException catch (e) {
        _log.info('Rattrapage de ${gap.markerId} reporté (serveur absent): $e');
        return result == _Part.saved ? _Part.cut : _Part.unavailable;
      } catch (e) {
        _log.warning('Rattrapage de ${gap.markerId} échoué, repère gardé: $e');
        return result == _Part.saved ? _Part.cut : _Part.failed;
      }
      List<({int offsetMs, String text})> kept = trimOverlaps(
        pieces,
        before: before,
        after: last ? after : null,
      );
      if (edge != null) {
        final List<({int offsetMs, String text})> withEdge = trimOverlaps(
          pieces,
          before: before,
          after: edge.text,
        );
        if (!_sameTexts(withEdge, trimOverlaps(pieces, before: before))) {
          kept = withEdge;
          _intactEdges.add(edge.id);
        }
      }
      // Le départ recule dans la phrase intacte d'avant : le premier morceau
      // n'est souvent que sa fin, avec un mot qui diffère ou un début abîmé
      // (sonde 9 : « L'Omavois, puis la gardienne… »). Un morceau d'avant la
      // perte presque tout entier dans ce voisin (60 % de ses mots, dans
      // l'ordre) est écarté ; celui qui dit autre chose reste.
      // ponytail: coupe sur le texte ; partir du premier silence entre
      // phrases (WAV) serait la racine, si le banc avait de vrais silences.
      // Même chose au début d'une tranche suivante : la fin d'une phrase déjà
      // rendue entière par la tranche d'avant.
      if (before != null &&
          kept.isNotEmpty &&
          (first
              ? gap.startMs + kept.first.offsetMs < marker.timestampMs
              : kept.first.offsetMs < 500) &&
          _sharedInOrder(kept.first.text, before) >= _tailRepeat) {
        kept = kept.sublist(1);
      }
      if (result == _Part.noAudio) result = _Part.nothingNew;
      if (kept.isNotEmpty) {
        result = _Part.saved;
        _progressed = true;
        for (int k = 0; k < kept.length; k++) {
          final int at = from + kept[k].offsetMs;
          await _transcripts.save(
            _lastRecovered[gap.source] = TranscriptSegmentEntity(
              // Par l'heure : une tentative qui reprend n'écrase pas les
              // tranches déjà rendues ; une reprise du même audio, si.
              id: '$prefix${at}_$k',
              sessionId: sessionId,
              source: gap.source,
              text: kept[k].text,
              timestampMs: at,
              createdAt: clock.now(),
            ),
          );
        }
        before = kept.last.text;
        if (!last) {
          // Ce qui est rendu sort du repère ; les phrases qu'il remplace
          // partent (rien n'est supprimé avant d'être rendu).
          for (final String id in gap.replacedIds) {
            final TranscriptSegmentEntity? s = segments
                .where((TranscriptSegmentEntity x) => x.id == id)
                .firstOrNull;
            if (s != null &&
                s.timestampMs < to &&
                !_isMarker(s) &&
                !_intactEdges.contains(id)) {
              await _transcripts.deleteById(id);
            }
          }
          if (lostEnd != null && to < lostEnd) {
            marker = marker.copyWith(
              text: LiveTranscriptionService.gapMarkerText(to, lostEnd),
              timestampMs: to,
            );
            await _transcripts.save(marker);
          }
        }
      }
      from = to;
    }
    return result;
  }

  /// Tranche d'audio d'un appel au transcripteur (plus un reste de moins de
  /// [_minTail]) : une tentative coupée garde ce qu'elle a rendu (un trou de
  /// 8 min, sonde 9). Un trou plus court part en un appel, comme avant.
  // ponytail: borne fixe, coupée au dernier silence de ses 10 s de fin ;
  // une phrase sans pause à la borne est coupée en deux morceaux.
  static const Duration slice = Duration(seconds: 100);
  static const Duration _minTail = Duration(seconds: 15);

  /// [pcm] coupé après le dernier silence (pas de 100 ms) de ses 10
  /// dernières secondes, pour ne pas couper une phrase ; sinon tel quel.
  static Uint8List _cutAtSilence(Uint8List pcm) {
    const int step = 3200;
    final int chunks = pcm.length ~/ step;
    for (int c = chunks - 1; c > 0 && c >= chunks - 100; c--) {
      if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(
        Uint8List.sublistView(pcm, c * step, (c + 1) * step),
      )) {
        return Uint8List.sublistView(pcm, 0, (c + 1) * step);
      }
    }
    return pcm;
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
      if (s.id == marker.id || s.source != marker.source || _isMarker(s)) {
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

  static const double _tailRepeat = 0.6;

  /// Part des mots de [piece], dans l'ordre, retrouvés dans [neighbour].
  static double _sharedInOrder(String piece, String neighbour) {
    final List<String> a = _keys(_words(piece));
    final List<String> b = _keys(_words(neighbour));
    if (a.isEmpty) return 0;
    List<int> prev = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      final List<int> cur = List<int>.filled(b.length + 1, 0);
      for (int j = 1; j <= b.length; j++) {
        cur[j] = a[i - 1] == b[j - 1]
            ? prev[j - 1] + 1
            : math.max(prev[j], cur[j - 1]);
      }
      prev = cur;
    }
    return prev[b.length] / a.length;
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

  static bool _sameTexts(
    List<({int offsetMs, String text})> a,
    List<({int offsetMs, String text})> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text) return false;
    }
    return true;
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

/// Issue d'un morceau de repère.
// cut : une partie rendue, puis le transcripteur a manqué (la suite reprend
// à la prochaine tentative, le repère rétréci).
enum _Part { noAudio, unavailable, failed, nothingNew, saved, cut }

/// Union de repères de perte d'une source : le premier (par début), la fin
/// la plus tardive, et les autres repères qu'elle absorbe.
class _MarkerUnion {
  _MarkerUnion(this.first, this.end);

  final TranscriptSegmentEntity first;
  int end;

  /// Début de l'union suivante de la même source, s'il y en a une.
  int? nextStart;
  final List<String> others = <String>[];
}
