import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/repositories/session.repository.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
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
    await RepairInterruptedSessionsUseCase(
      sessionRepository: _sessions,
      transcriptRepository: _transcripts,
    ).invoke();
    for (final SessionEntity session in killed) {
      final List<TranscriptSegmentEntity> segments = await _transcripts
          .getBySessionId(session.id);
      for (final (AudioSource source, String track) in <(AudioSource, String)>[
        (AudioSource.input, 'mic'),
        (AudioSource.output, 'system'),
      ]) {
        final Duration? wav = await WavRecorder.recordedDuration(
          '$_recordingsDir/${session.id}_$track.wav',
        );
        final List<int> lines = <int>[
          for (final TranscriptSegmentEntity s in segments)
            if (s.source == source) s.timestampMs,
        ];
        // Source jamais enregistrée : rien ne manque.
        if (lines.isEmpty && (wav == null || wav == Duration.zero)) continue;
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
  }
}
