import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictated_intervals.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../../helpers/live_service_fakes.dart';

/// Dictée (T2) pendant une réunion : ses mots ne reviennent dans la note par
/// AUCUNE passe faite plus tard sur le WAV micro.
///
/// Où : `<recordings>/<sessionId>_dictations.json`, à côté des WAV de la
/// session (pas de changement de schéma ; part avec les WAV) :
/// `[{"source": "input", "startMs": int, "endMs": int}, …]`, ms depuis le
/// début de la réunion (même repère que les WAV et les segments).
///
/// API supposée (lib/application/services/dictation/dictated_intervals.dart) :
/// - `DictatedInterval({required int startMs, required int endMs})` ;
/// - `DictatedIntervalsStore(String recordingsDirectory)`,
///   `void add(String sessionId, DictatedInterval)`,
///   `List<DictatedInterval> read(String sessionId)` — synchrones (fichier de quelques octets, comme PrefsStore) ;
/// - `Uint8List muteDictatedIntervals(Uint8List wav, List<DictatedInterval>)`
///   : entrée de la diarization post-réunion, WAV micro avec ces intervalles
///   en silence (en-tête et durée gardés, heures inchangées) ;
/// - `GapBackfillService.plan(segments, {List<DictatedInterval> dictated})`
///   : les repères micro sont retranscrits hors de ces intervalles ;
///   `GapBackfillService(..., DictatedIntervalsStore? dictatedIntervals)`
///   les lit pour la session.
///
/// Une perte entièrement dans une dictée n'a rien fait perdre à la réunion :
/// son repère quitte la note au rattrapage, sans rien envoyer au serveur, et
/// même serveur absent (il ne reste pas « en attente »).
///
/// Le coach (après l'appel) lit les segments micro de la note, où la dictée
/// n'est jamais sauvée (dictation_during_meeting_test) : rien à exclure.
void main() {
  const String sessionId = '1700000000000';

  group('stockage avec la session', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_dictated_');
    });
    tearDown(() => dir.delete(recursive: true));

    test('enregistrés puis relus par une autre instance, dans l ordre', () {
      DictatedIntervalsStore(dir.path)
        ..add(sessionId, const DictatedInterval(startMs: 2000, endMs: 5000))
        ..add(sessionId, const DictatedInterval(startMs: 9000, endMs: 9800));

      final List<DictatedInterval> read = DictatedIntervalsStore(
        dir.path,
      ).read(sessionId);

      expect(
        read.map((DictatedInterval i) => (i.startMs, i.endMs)).toList(),
        <(int, int)>[(2000, 5000), (9000, 9800)],
      );
    });

    test('fichier à côté des WAV : session, source micro, début et fin', () {
      DictatedIntervalsStore(
        dir.path,
      ).add(sessionId, const DictatedInterval(startMs: 2000, endMs: 5000));

      final File file = File('${dir.path}/${sessionId}_dictations.json');
      expect(file.existsSync(), isTrue);
      expect(jsonDecode(file.readAsStringSync()), <Object>[
        <String, Object>{'source': 'input', 'startMs': 2000, 'endMs': 5000},
      ]);
    });

    test('une autre session ne voit rien ; fichier absent ou abîmé : vide', () {
      DictatedIntervalsStore(
        dir.path,
      ).add(sessionId, const DictatedInterval(startMs: 0, endMs: 1000));
      File('${dir.path}/other_dictations.json').writeAsStringSync('{abîmé');

      expect(DictatedIntervalsStore(dir.path).read('absent'), isEmpty);
      expect(DictatedIntervalsStore(dir.path).read('other'), isEmpty);
    });
  });

  group('diarization : WAV micro sans la dictée', () {
    /// WAV de 1 s (en-tête 44 octets) dont chaque échantillon vaut 1000.
    Uint8List wav() {
      final Uint8List bytes = Uint8List(44 + 32000);
      bytes.setRange(0, 4, ascii.encode('RIFF'));
      final ByteData data = ByteData.sublistView(bytes);
      for (int i = 44; i < bytes.length; i += 2) {
        data.setInt16(i, 1000, Endian.little);
      }
      return bytes;
    }

    int sampleAt(Uint8List bytes, int ms) =>
        ByteData.sublistView(bytes).getInt16(44 + ms * 32, Endian.little);

    test('intervalles en silence, le reste et la durée intacts', () {
      final Uint8List original = wav();

      final Uint8List muted = muteDictatedIntervals(
        original,
        const <DictatedInterval>[DictatedInterval(startMs: 200, endMs: 400)],
      );

      expect(muted.length, original.length);
      expect(muted.sublist(0, 44), original.sublist(0, 44));
      expect(sampleAt(muted, 199), 1000);
      expect(sampleAt(muted, 200), 0);
      expect(sampleAt(muted, 399), 0);
      expect(sampleAt(muted, 400), 1000);
      expect(sampleAt(original, 300), 1000, reason: 'entrée non modifiée');
    });

    test('intervalle qui dépasse la fin : coupé à la fin, sans lever', () {
      final Uint8List muted = muteDictatedIntervals(
        wav(),
        const <DictatedInterval>[DictatedInterval(startMs: 900, endMs: 5000)],
      );

      expect(sampleAt(muted, 899), 1000);
      expect(sampleAt(muted, 999), 0);
    });

    test('sans intervalle : identique', () {
      expect(muteDictatedIntervals(wav(), const <DictatedInterval>[]), wav());
    });
  });

  group('rattrapage des pertes : jamais sur la dictée', () {
    TranscriptSegmentEntity marker(
      String id,
      AudioSource source,
      int s,
      int e,
    ) => TranscriptSegmentEntity(
      id: id,
      sessionId: sessionId,
      source: source,
      text: LiveTranscriptionService.gapMarkerText(s, e),
      timestampMs: s,
      createdAt: DateTime(2026, 11, 22, 10),
    );
    final int margin = GapBackfillService.margin.inMilliseconds;
    const DictatedInterval dictation = DictatedInterval(
      startMs: 13000,
      endMs: 15000,
    );

    test('une perte micro qui contient une dictée est retranscrite de part '
        'et d autre', () {
      final plan = GapBackfillService.plan(
        <TranscriptSegmentEntity>[marker('m', AudioSource.input, 10000, 20000)],
        dictated: const <DictatedInterval>[dictation],
      );

      expect(
        plan.map((p) => (p.markerId, p.startMs, p.endMs)).toList(),
        <(String, int, int)>[
          ('m', 10000 - margin, 13000),
          ('m', 15000, 20000 + margin),
        ],
      );
    });

    test('une perte entièrement dictée : rien à retranscrire', () {
      final plan = GapBackfillService.plan(
        <TranscriptSegmentEntity>[marker('m', AudioSource.input, 13000, 14000)],
        dictated: const <DictatedInterval>[
          DictatedInterval(startMs: 11000, endMs: 16000),
        ],
      );

      expect(plan, isEmpty);
    });

    test('perte entièrement dictée : repère retiré de la note, rien envoyé, '
        'même serveur absent', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'oats_dictated_inside_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_mic.wav');
      for (int id = 0; id < 300; id++) {
        await recorder.append(Uint8List(3200));
      }
      await recorder.close();
      DictatedIntervalsStore(dir.path).add(sessionId, dictation);
      final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
      await repo.save(marker('inside', AudioSource.input, 13200, 14800));
      final _RecordingTranscriber transcriber = _RecordingTranscriber()
        ..unavailable = true;

      final BackfillOutcome outcome = await GapBackfillService(
        transcriber: transcriber,
        transcripts: repo,
        isRecording: () => false,
        dictatedIntervals: DictatedIntervalsStore(dir.path),
      ).backfill(sessionId, recordingsDirectory: dir.path);

      expect(repo.store.containsKey('inside'), isFalse);
      expect(transcriber.calls, isEmpty);
      expect(outcome.markersLeft, 0);
    });

    test(
      'une perte du son du Mac n est pas touchée (la dictée est au micro)',
      () {
        final plan = GapBackfillService.plan(
          <TranscriptSegmentEntity>[
            marker('s', AudioSource.output, 10000, 20000),
          ],
          dictated: const <DictatedInterval>[dictation],
        );

        expect(plan.single.startMs, 10000 - margin);
        expect(plan.single.endMs, 20000 + margin);
      },
    );

    test(
      'bout en bout : l audio dicté n est jamais envoyé au serveur',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'oats_dictated_backfill_',
        );
        addTearDown(() => dir.delete(recursive: true));
        final WavRecorder recorder = WavRecorder();
        await recorder.open('${dir.path}/${sessionId}_mic.wav');
        for (int id = 0; id < 300; id++) {
          final Uint8List data = Uint8List(3200);
          ByteData.sublistView(data)
            ..setInt16(0, id & 0x7FFF, Endian.little)
            ..setInt16(2, id >> 15, Endian.little);
          await recorder.append(data);
        }
        await recorder.close();
        DictatedIntervalsStore(dir.path).add(sessionId, dictation);
        final InMemoryTranscriptRepository repo =
            InMemoryTranscriptRepository();
        await repo.save(marker('m', AudioSource.input, 10000, 20000));
        final _RecordingTranscriber transcriber = _RecordingTranscriber();

        await GapBackfillService(
          transcriber: transcriber,
          transcripts: repo,
          isRecording: () => false,
          dictatedIntervals: DictatedIntervalsStore(dir.path),
        ).backfill(sessionId, recordingsDirectory: dir.path);

        final Set<int> sentIds = <int>{
          for (final Uint8List pcm in transcriber.calls)
            for (int at = 0; at + 4 <= pcm.length; at += 3200)
              ByteData.sublistView(pcm).getInt16(at, Endian.little) +
                  (ByteData.sublistView(pcm).getInt16(at + 2, Endian.little) <<
                      15),
        };
        expect(sentIds, isNotEmpty);
        expect(
          sentIds.where((int id) => id >= 130 && id < 150),
          isEmpty,
          reason: 'chunks 13,0 s à 15,0 s = dictée',
        );
      },
    );
  });
}

/// Transcripteur factice : garde chaque PCM reçu, rend une phrase.
final class _RecordingTranscriber implements PcmTranscriber {
  final List<Uint8List> calls = <Uint8List>[];

  /// Serveur absent : chaque appel lève [TranscriberUnavailable].
  bool unavailable = false;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls.add(pcm);
    if (unavailable) throw const TranscriberUnavailable('serveur absent');
    return <({int offsetMs, String text})>[
      (offsetMs: 0, text: 'Retrouvé ${calls.length}.'),
    ];
  }
}
