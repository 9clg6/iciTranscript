import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

/// Réparation au lancement des sessions restées `active` (app tuée, disque
/// plein) : la session passe `interrupted`, et chaque source enregistrée
/// reçoit un repère OUVERT à son dernier point durable (le plus tardif de
/// son dernier segment rangé et de la fin de son WAV) : rien n'a pu être
/// gardé après, ni texte ni audio. Écrit ici parce qu'au relancement il y a
/// de nouveau de la place ; disque plein, rien ne peut s'écrire.
final class LaunchRepair {
  /// Cree une instance de [LaunchRepair].
  LaunchRepair({
    required SessionRepository sessions,
    required TranscriptRepository transcripts,
    required String recordingsDir,
  }) : _sessions = sessions,
       _transcripts = transcripts,
       _recordingsDir = recordingsDir;

  final SessionRepository _sessions;
  final TranscriptRepository _transcripts;
  final String _recordingsDir;

  /// Répare ; une session déjà réparée (plus `active`) n'est pas touchée.
  Future<void> run() async {
    final List<SessionEntity> killed = <SessionEntity>[
      for (final SessionEntity s in await _sessions.getAll())
        if (s.status == SessionStatus.active) s,
    ];
    // Les repères d'abord, la session `interrupted` en dernier : une app
    // tuée en cours de route la retrouve `active` et refait tout (ids stables).
    for (final SessionEntity session in killed) {
      final List<TranscriptSegmentEntity> segments = await _transcripts
          .getBySessionId(session.id);
      for (final (AudioSource source, String track) in <(AudioSource, String)>[
        (AudioSource.input, 'mic'),
        (AudioSource.output, 'system'),
      ]) {
        final String path = '$_recordingsDir/${session.id}_$track.wav';
        final Duration? wav = await WavRecorder.recordedDuration(path);
        final List<int> lines = <int>[
          for (final TranscriptSegmentEntity s in segments)
            if (s.source == source) s.timestampMs,
        ];
        // Source jamais enregistrée : rien ne manque.
        if (lines.isEmpty && (wav == null || wav == Duration.zero)) continue;
        // (a) Parole du WAV sans ligne rangée ni repère (lignes que la base
        // refusait, gardées en mémoire seulement, rangées dans le désordre) :
        // un repère de perte ordinaire, que le rattrapage retranscrit.
        for (final (int from, int to) in await _unstoredSpeech(
          path,
          segments.where((TranscriptSegmentEntity x) => x.source == source),
        )) {
          await _transcripts.save(
            TranscriptSegmentEntity(
              id: '${session.id}_${source.name}_relaunch_gap_$from',
              sessionId: session.id,
              source: source,
              text: LiveTranscriptionService.gapMarkerText(from, to),
              timestampMs: from,
              createdAt: clock.now(),
            ),
          );
        }
        // (b) Rien de gardé après la fin du WAV (ni après la dernière ligne).
        final int last = math.max(
          wav?.inMilliseconds ?? 0,
          lines.isEmpty ? 0 : lines.reduce(math.max),
        );
        await _transcripts.save(
          TranscriptSegmentEntity(
            id: '${session.id}_${source.name}_not_recorded_after',
            sessionId: session.id,
            source: source,
            text: LiveTranscriptionService.notRecordedAfterMarkerText(last),
            timestampMs: last,
            createdAt: clock.now(),
          ),
        );
      }
    }
    await RepairInterruptedSessionsUseCase(
      sessionRepository: _sessions,
      transcriptRepository: _transcripts,
    ).invoke();
  }

  // Parole plus courte : ignorée (une respiration, un bruit).
  static const int _minSpeechMs = 1000;
  // Deux passages sans ligne plus proches que cela : un seul repère.
  static const int _mergeMs = 5000;
  // Une ligne porte l'heure du début de sa phrase, à peu près.
  static const int _lineSlackMs = 2000;

  /// Passages de parole du WAV [path] (porte RMS du direct) qu'aucune ligne
  /// ni aucun repère de [lines] ne couvre, fusionnés s'ils sont proches.
  static Future<List<(int, int)>> _unstoredSpeech(
    String path,
    Iterable<TranscriptSegmentEntity> lines,
  ) async {
    final File file = File(path);
    if (!file.existsSync()) return const <(int, int)>[];
    final RandomAccessFile raf = await file.open();
    final List<(int, int)> runs = <(int, int)>[];
    try {
      const int step = 3200; // 100 ms
      await raf.setPosition(44); // en-tête WAV
      int? start;
      int lastSpeech = 0;
      for (int c = 0; ; c++) {
        final Uint8List chunk = await raf.read(step);
        if (chunk.length < step) break;
        if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(chunk)) continue;
        final int at = c * 100;
        if (start != null && at - lastSpeech > TranscriptionRemoteDataSourceImpl.silenceToFinalizeMs) {
          runs.add((start, lastSpeech + 100));
          start = null;
        }
        start ??= at;
        lastSpeech = at;
      }
      if (start != null) runs.add((start, lastSpeech + 100));
    } finally {
      await raf.close();
    }

    // Heures couvertes : une ligne, de 2 s avant son heure jusqu'à la ligne
    // suivante ou à la fin de sa phrase parlée (au plus `maxUtteranceMs`) ; un repère,
    // sa plage écrite.
    final List<TranscriptSegmentEntity> stored =
        lines
            .where((TranscriptSegmentEntity l) => !isTranscriptMarker(l.text))
            .toList()
          ..sort(
            (TranscriptSegmentEntity a, TranscriptSegmentEntity b) =>
                a.timestampMs.compareTo(b.timestampMs),
          );
    final List<(int, int)> covers = <(int, int)>[];
    for (int i = 0; i < stored.length; i++) {
      final int at = stored[i].timestampMs;
      // Jusqu'à la fin du passage de parole de la ligne (prochaine pause).
      int end = at;
      for (final (int, int) r in runs) {
        if (r.$1 <= at + _lineSlackMs && r.$2 > at) {
          end = r.$2;
          break;
        }
      }
      end = math.min(
        end,
        at + TranscriptionRemoteDataSourceImpl.maxUtteranceMs,
      );
      covers.add((
        at - _lineSlackMs,
        i + 1 < stored.length ? math.min(stored[i + 1].timestampMs, end) : end,
      ));
    }
    for (final TranscriptSegmentEntity l in lines) {
      final RegExpMatch? m = isTranscriptMarker(l.text)
          ? _times.firstMatch(l.text)
          : null;
      if (m != null) covers.add((_ms(m, 1), _ms(m, 4)));
    }
    covers.sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));

    final List<(int, int)> out = <(int, int)>[];
    for (final (int, int) run in runs) {
      int cursor = run.$1;
      final List<(int, int)> holes = <(int, int)>[];
      for (final (int, int) c in covers) {
        if (c.$2 <= cursor) continue;
        if (c.$1 >= run.$2) break;
        if (c.$1 > cursor) holes.add((cursor, c.$1));
        cursor = math.max(cursor, c.$2);
      }
      if (cursor < run.$2) holes.add((cursor, run.$2));
      for (final (int, int) h in holes) {
        if (h.$2 - h.$1 < _minSpeechMs) continue;
        if (out.isNotEmpty && h.$1 - out.last.$2 <= _mergeMs) {
          out.last = (out.last.$1, h.$2);
        } else {
          out.add(h);
        }
      }
    }
    return out;
  }

  static final RegExp _times = RegExp(
    r'(\d+):(\d{2}):(\d{2})\s*[–-]\s*(\d+):(\d{2}):(\d{2})',
  );

  static int _ms(RegExpMatch m, int first) =>
      ((int.parse(m.group(first)!) * 60 + int.parse(m.group(first + 1)!)) * 60 +
          int.parse(m.group(first + 2)!)) *
      1000;
}
