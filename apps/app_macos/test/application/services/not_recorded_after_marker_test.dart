import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/launch_repair.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/live_service_fakes.dart';

// Repère OUVERT écrit au relancement (décision du coordinateur, revue de
// la PR #31) : pour une session restée active (app tuée, disque plein),
// chaque source enregistrée reçoit « Rien n'a pu être enregistré après
// hh:mm:ss (app arrêtée ou disque plein) » à son dernier point durable —
// le plus tardif entre son dernier segment rangé et la fin de son WAV.
//
// API supposée :
// - `LiveTranscriptionService.notRecordedAfterMarkerText(int startMs)` et
//   `isNotRecordedAfterMarker(String)` ; `isTranscriptMarker` (prédicat
//   partagé : questions, coach, résumé) le reconnaît ;
// - `WavRecorder.recordedDuration(String path)` : durée d'audio du WAV
//   (longueur − 44 octets, 32 o/ms), null sans fichier ;
// - `LaunchRepair({required SessionRepository sessions, required
//   TranscriptRepository transcripts, required String recordingsDir})
//   .run()` : passe les sessions `active` à `interrupted` (comme
//   `RepairInterruptedSessionsUseCase`) et écrit les repères ouverts ; le
//   lancement (`kernel.provider.dart`, `_repairAfterCrash`) l'appelle à la
//   place du seul cas d'usage ;
// - affichage localisé : clé `transcription.gap.not_recorded_after`
//   (`{}` = heure).
const String _session = '1700000000000';

TranscriptSegmentEntity _line(String id, AudioSource source, int atMs) =>
    TranscriptSegmentEntity(
      id: id,
      sessionId: _session,
      source: source,
      text: 'Phrase $id.',
      timestampMs: atMs,
      createdAt: DateTime(2026, 11, 25),
    );

Future<void> _wav(String path, int ms) async {
  final WavRecorder r = WavRecorder();
  await r.open(path);
  await r.append(Uint8List(ms * 32));
  await r.close();
}

void main() {
  group('texte et prédicat', () {
    test('texte du repère, une seule heure', () {
      expect(
        LiveTranscriptionService.notRecordedAfterMarkerText(90000),
        "Rien n'a pu être enregistré après 00:01:30 "
        '(app arrêtée ou disque plein)',
      );
    });

    test('reconnu par son prédicat et par le prédicat partagé des repères '
        '(exclu des questions, du coach et du résumé)', () {
      final String m = LiveTranscriptionService.notRecordedAfterMarkerText(
        90000,
      );
      expect(LiveTranscriptionService.isNotRecordedAfterMarker(m), isTrue);
      expect(isTranscriptMarker(m), isTrue);
      expect(
        LiveTranscriptionService.isNotRecordedAfterMarker(
          LiveTranscriptionService.gapMarkerText(1000, 2000),
        ),
        isFalse,
      );
      expect(
        LiveTranscriptionService.isNotRecordedAfterMarker(
          LiveTranscriptionService.noAudioCopyMarkerText(1000, 2000),
        ),
        isFalse,
      );
      expect(
        LiveTranscriptionService.isNotRecordedAfterMarker(
          "Rien n'a pu être dit, dit-il.",
        ),
        isFalse,
      );
    });
  });

  group('réparation au lancement', () {
    late Directory dir;
    late InMemorySessionRepository sessions;
    late InMemoryTranscriptRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_launch_repair_');
      sessions = InMemorySessionRepository();
      repo = InMemoryTranscriptRepository();
    });
    tearDown(() => dir.delete(recursive: true));

    Future<void> run() => LaunchRepair(
      sessions: sessions,
      transcripts: repo,
      recordingsDir: dir.path,
    ).run();

    List<TranscriptSegmentEntity> openMarkers() => repo.store.values
        .where(
          (TranscriptSegmentEntity s) =>
              LiveTranscriptionService.isNotRecordedAfterMarker(s.text),
        )
        .toList();

    test('durée lue dans le WAV', () async {
      await _wav('${dir.path}/x_mic.wav', 12300);
      expect(
        await WavRecorder.recordedDuration('${dir.path}/x_mic.wav'),
        const Duration(milliseconds: 12300),
      );
      expect(
        await WavRecorder.recordedDuration('${dir.path}/absent.wav'),
        isNull,
      );
    });

    test('session tuée : un repère ouvert par source, au plus tardif du '
        'dernier segment et de la fin du WAV ; session interrompue', () async {
      sessions.store[_session] = FakeData.createSession(
        id: _session,
        status: SessionStatus.active,
      );
      await repo.save(_line('m1', AudioSource.input, 40000));
      await repo.save(_line('s1', AudioSource.output, 40000));
      await _wav('${dir.path}/${_session}_mic.wav', 50000); // WAV plus tard
      await _wav(
        '${dir.path}/${_session}_system.wav',
        30000,
      ); // segment plus tard

      await run();

      expect(sessions.store[_session]!.status, SessionStatus.interrupted);
      final List<TranscriptSegmentEntity> open = openMarkers();
      expect(open, hasLength(2));
      final TranscriptSegmentEntity mic = open.singleWhere(
        (TranscriptSegmentEntity s) => s.source == AudioSource.input,
      );
      final TranscriptSegmentEntity sys = open.singleWhere(
        (TranscriptSegmentEntity s) => s.source == AudioSource.output,
      );
      expect(mic.timestampMs, 50000);
      expect(
        mic.text,
        LiveTranscriptionService.notRecordedAfterMarkerText(50000),
      );
      expect(sys.timestampMs, greaterThanOrEqualTo(40000));
      expect(sys.timestampMs, lessThan(48000));
      expect(mic.id, isNot(sys.id));
    });

    test('micro seul : un seul repère', () async {
      sessions.store[_session] = FakeData.createSession(
        id: _session,
        status: SessionStatus.active,
      );
      await repo.save(_line('m1', AudioSource.input, 10000));
      await _wav('${dir.path}/${_session}_mic.wav', 20000);
      await run();
      expect(openMarkers(), hasLength(1));
      expect(openMarkers().single.source, AudioSource.input);
    });

    test('session finie proprement : aucun repère', () async {
      sessions.store[_session] = FakeData.createSession(
        id: _session,
        status: SessionStatus.completed,
      );
      await repo.save(_line('m1', AudioSource.input, 10000));
      await _wav('${dir.path}/${_session}_mic.wav', 20000);
      await run();
      expect(openMarkers(), isEmpty);
    });

    test('lancé deux fois : pas de second repère', () async {
      sessions.store[_session] = FakeData.createSession(
        id: _session,
        status: SessionStatus.active,
      );
      await _wav('${dir.path}/${_session}_mic.wav', 20000);
      await run();
      await run();
      expect(openMarkers(), hasLength(1));
    });

    test('le rattrapage ne le retire jamais, même devant du silence', () async {
      sessions.store[_session] = FakeData.createSession(
        id: _session,
        status: SessionStatus.active,
      );
      await repo.save(_line('m1', AudioSource.input, 10000));
      // WAV de 60 s de silence (zéros) : rien à dire après 20 s.
      await _wav('${dir.path}/${_session}_mic.wav', 60000);
      await repo.save(
        TranscriptSegmentEntity(
          id: 'open',
          sessionId: _session,
          source: AudioSource.input,
          text: LiveTranscriptionService.notRecordedAfterMarkerText(20000),
          timestampMs: 20000,
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      await GapBackfillService(
        transcriber: _Nothing(),
        transcripts: repo,
        isRecording: () => false,
      ).backfill(_session, recordingsDirectory: dir.path);
      expect(repo.store.containsKey('open'), isTrue);
    });
  });
}

final class _Nothing implements PcmTranscriber {
  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      const <({int offsetMs, String text})>[];
}
