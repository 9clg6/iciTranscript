import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../fixtures/probe5_sequences.dart';
import '../fixtures/probe7_overlap.dart';
import 'live_service_fakes.dart';

/// Session enregistrée par une sonde : l'état rangé avant le rattrapage
/// (repères compris), le texte que le vrai rattrapage a rendu (heures de
/// réunion), chaque intervalle qu'il a retranscrit et le texte lu.
final class RecordedSession {
  const RecordedSession({
    required this.name,
    required this.sessionId,
    required this.stored,
    required this.recovered,
    required this.recordedStarts,
    this.reference = probeReference,
  });

  factory RecordedSession.fromScenario(
    ProbeScenario sc, {
    List<ProbeSentence> reference = probeReference,
  }) => RecordedSession(
    name: sc.name,
    reference: reference,
    sessionId: sc.sessionId,
    stored: <TranscriptSegmentEntity>[
      for (final ProbeSegment s in sc.segments)
        TranscriptSegmentEntity(
          id: s.id,
          sessionId: sc.sessionId,
          source: sourceOf(s.source),
          text: s.text,
          timestampMs: s.timestampMs,
          createdAt: DateTime(2026, 11, 23),
        ),
      for (final ProbeGap g in sc.gaps)
        TranscriptSegmentEntity(
          id: g.markerId,
          sessionId: sc.sessionId,
          source: sourceOf(g.source),
          text: LiveTranscriptionService.gapMarkerText(
            g.markerStartMs,
            g.markerEndMs,
          ),
          timestampMs: g.markerStartMs,
          createdAt: DateTime(2026, 11, 23),
        ),
    ],
    recovered: <RecoveredPiece>[
      for (final ProbeGap g in sc.gaps)
        for (final ({int offsetMs, String text}) p in g.recovered)
          (
            source: g.source,
            fromMs: g.planStartMs,
            atMs: g.planStartMs + p.offsetMs,
            text: p.text,
          ),
    ],
    recordedStarts: <RecordedInterval>[
      for (final ProbeGap g in sc.gaps)
        (source: g.source, startMs: g.planStartMs, endMs: g.markerEndMs + 1000),
    ],
  );

  /// Sonde 7 : son système seul ; l'intervalle rattrapé commence 1 s avant
  /// chaque repère.
  factory RecordedSession.probe7() {
    // Repères rangés qui se recoupent : le vrai rattrapage a retranscrit une
    // fois chaque union, à partir d'1 s avant elle.
    final List<({int startMs, int endMs})> ranges =
        <({int startMs, int endMs})>[
          for (final Probe7Segment s in probe7SystemStored)
            if (markerRange(s.text) != null)
              (startMs: s.timestampMs, endMs: markerRange(s.text)!.endMs),
        ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final List<int> starts = <int>[];
    final List<int> ends = <int>[];
    int unionEnd = -1;
    for (final ({int startMs, int endMs}) r in ranges) {
      if (r.startMs > unionEnd) {
        starts.add(r.startMs - 1000);
        ends.add(r.endMs + 1000);
      }
      unionEnd = math.max(unionEnd, r.endMs);
      ends.last = unionEnd + 1000;
    }
    // Chaque morceau rendu appartient à la dernière union commencée avant lui.
    int fromOf(int atMs) => starts.lastWhere(
      (int s) => s <= atMs + 1500,
      orElse: () => starts.first,
    );
    return RecordedSession(
      name: 'Dlag (sonde 7)',
      sessionId: probe7SessionId,
      stored: <TranscriptSegmentEntity>[
        for (final Probe7Segment s in probe7SystemStored)
          TranscriptSegmentEntity(
            id: s.id,
            sessionId: probe7SessionId,
            source: AudioSource.output,
            text: s.text,
            timestampMs: s.timestampMs,
            createdAt: DateTime(2026, 11, 24),
          ),
      ],
      recovered: <RecoveredPiece>[
        for (final ({int atMs, String text}) p in probe7SystemRecovered)
          (
            source: 'output',
            fromMs: fromOf(p.atMs),
            atMs: p.atMs,
            text: p.text,
          ),
      ],
      recordedStarts: <RecordedInterval>[
        for (int i = 0; i < starts.length; i++)
          (source: 'output', startMs: starts[i], endMs: ends[i]),
      ],
    );
  }

  final String name;
  final String sessionId;
  final List<TranscriptSegmentEntity> stored;
  final List<RecoveredPiece> recovered;
  final List<RecordedInterval> recordedStarts;
  final List<ProbeSentence> reference;

  Set<AudioSource> get sources => <AudioSource>{
    for (final TranscriptSegmentEntity s in stored) s.source,
  };

  /// Fin de la session : le dernier repère ou segment rangé.
  int get endMs => stored
      .map(
        (TranscriptSegmentEntity s) =>
            markerRange(s.text)?.endMs ?? s.timestampMs,
      )
      .reduce(math.max);
}

/// Morceau rendu par le vrai rattrapage : sa source, le début de
/// l'intervalle retranscrit qui l'a rendu, son heure de réunion, son texte.
typedef RecoveredPiece = ({String source, int fromMs, int atMs, String text});

/// Intervalle que le vrai rattrapage a retranscrit.
typedef RecordedInterval = ({String source, int startMs, int endMs});

AudioSource sourceOf(String s) =>
    s == 'input' ? AudioSource.input : AudioSource.output;

bool isMarker(String text) =>
    text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
    LiveTranscriptionService.isUntranscribedMarker(text);

/// Heures (ms, à la seconde) d'un repère de perte ou de passage non
/// transcrit ; null pour une phrase.
({int startMs, int endMs})? markerRange(String text) {
  if (!isMarker(text)) return null;
  final List<int> times = <int>[
    for (final RegExpMatch m in RegExp(
      r'(\d+):(\d{2}):(\d{2})',
    ).allMatches(text))
      ((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 60 +
              int.parse(m.group(3)!)) *
          1000,
  ];
  return times.length < 2 ? null : (startMs: times[0], endMs: times[1]);
}

/// Range l'état enregistré, écrit les deux WAV (chaque échantillon d'un pas
/// de 100 ms vaut numéro × 4 + piste : 1 micro, 2 système) et lance le
/// rattrapage. Rend le dépôt après le rattrapage.
Future<InMemoryTranscriptRepository> runRecordedBackfill(
  RecordedSession session,
) async {
  final Directory dir = await Directory.systemTemp.createTemp(
    'oats_recorded_backfill_',
  );
  try {
    final int chunks = session.endMs ~/ 100 + 400;
    for (final (String track, int tag) in <(String, int)>[
      ('mic', 1),
      ('system', 2),
    ]) {
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${session.sessionId}_$track.wav');
      for (int c = 0; c < chunks; c++) {
        final Uint8List chunk = Uint8List(3200);
        final ByteData d = ByteData.sublistView(chunk);
        for (int o = 0; o < 3200; o += 2) {
          d.setInt16(o, c * 4 + tag, Endian.little);
        }
        await recorder.append(chunk);
      }
      await recorder.close();
    }
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    for (final TranscriptSegmentEntity s in session.stored) {
      await repo.save(s);
    }
    await GapBackfillService(
      transcriber: RecordedTranscriber(session),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(session.sessionId, recordingsDirectory: dir.path);
    return repo;
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Le serveur du rattrapage, d'après ce qu'il a réellement rendu.
/// - Intervalle qui commence là où le vrai a commencé (à 1,5 s près) : les
///   morceaux que celui-ci a rendus.
/// - Intervalle qui commence PLUS TARD, dans un intervalle enregistré : ses
///   morceaux qui commencent dans l'audio demandé (au plus 0,5 s avant) ;
///   ceux d'avant n'y sont pas entendus.
/// - Sinon (élargi, déplacé ailleurs) : les phrases lues dans cet audio ;
///   une phrase déjà commencée au début demandé rend sa fin (part des mots
///   au prorata du temps), comme le vrai serveur.
final class RecordedTranscriber implements PcmTranscriber {
  RecordedTranscriber(this.session);

  final RecordedSession session;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final int v = ByteData.sublistView(pcm).getInt16(0, Endian.little);
    final String source = v % 4 == 1 ? 'input' : 'output';
    final int startMs = (v ~/ 4) * 100;
    final int endMs = startMs + pcm.length ~/ 32;
    final RecordedInterval? same = session.recordedStarts
        .where(
          (RecordedInterval r) =>
              r.source == source && (r.startMs - startMs).abs() <= 1500,
        )
        .firstOrNull;
    if (same != null) {
      return <({int offsetMs, String text})>[
        for (final RecoveredPiece p in session.recovered)
          if (p.source == source &&
              (p.fromMs - same.startMs).abs() <= 1500 &&
              p.atMs < endMs)
            (offsetMs: math.max(0, p.atMs - startMs), text: p.text),
      ];
    }
    final RecordedInterval? inside = session.recordedStarts
        .where(
          (RecordedInterval r) =>
              r.source == source && r.startMs < startMs && startMs < r.endMs,
        )
        .firstOrNull;
    if (inside != null) {
      return <({int offsetMs, String text})>[
        for (final RecoveredPiece p in session.recovered)
          if (p.source == source &&
              (p.fromMs - inside.startMs).abs() <= 1500 &&
              p.atMs >= startMs - 500 &&
              p.atMs < endMs)
            (offsetMs: math.max(0, p.atMs - startMs), text: p.text),
      ];
    }
    return <({int offsetMs, String text})>[
      for (final ProbeSentence r in session.reference)
        if (r.source == source && r.startMs < endMs && r.endMs > startMs + 500)
          if (r.startMs >= startMs - 500)
            (offsetMs: math.max(0, r.startMs - startMs), text: r.text)
          else
            (offsetMs: 0, text: _tail(r, startMs)),
    ];
  }

  static String _tail(ProbeSentence r, int fromMs) {
    final List<String> all = r.text.split(' ');
    final int skip = (all.length * (fromMs - r.startMs) / (r.endMs - r.startMs))
        .round();
    return all.skip(skip).join(' ');
  }
}

List<String> words(String t) => t
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
    .split(RegExp(r'\s+'))
    .where((String w) => w.isNotEmpty)
    .toList();

/// Part des mots de [reference], dans l'ordre, retrouvés dans [line] (plus
/// longue sous-suite commune).
double coverage(String reference, String line) {
  final List<String> a = words(reference);
  final List<String> b = words(line);
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
