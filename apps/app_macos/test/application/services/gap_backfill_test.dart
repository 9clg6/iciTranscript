import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 5, point 6 : après la réunion, chaque repère « transcription
// interrompue » est retranscrit depuis le WAV de sa source, sur
// l'intervalle de la perte élargi d'une marge, et remplacé par les phrases
// retrouvées, dans l'ordre des heures. Échec : le repère reste. Jamais
// pendant un enregistrement ; deux passages donnent le même résultat ;
// sans repère, rien ne se passe.
//
// API supposée (lib/application/services/gap_backfill.service.dart) :
// - `abstract interface class PcmTranscriber { Future<List<({int offsetMs,
//   String text})>> transcribe(Uint8List pcm); }` : PCM16 mono 16 kHz,
//   morceaux datés depuis le début du PCM ;
// - `GapBackfillService({required PcmTranscriber transcriber, required
//   TranscriptRepository transcripts, required bool Function()
//   isRecording})`, `static const Duration margin` (1 s),
//   `static List<({String markerId, AudioSource source, int startMs, int
//   endMs})> plan(List<TranscriptSegmentEntity> segments)` (décision pure),
//   `Future<void> backfill(String sessionId, {required String
//   recordingsDirectory})`.
// WAV lus : `<dossier>/<sessionId>_mic.wav` et `_system.wav`.
void main() {
  const String sessionId = '1700000000000';
  final int margin = GapBackfillService.margin.inMilliseconds;

  TranscriptSegmentEntity segment(
    String id,
    AudioSource source,
    int timestampMs,
    String text,
  ) => TranscriptSegmentEntity(
    id: id,
    sessionId: sessionId,
    source: source,
    text: text,
    timestampMs: timestampMs,
    createdAt: DateTime(2026, 11, 22, 10),
  );

  TranscriptSegmentEntity marker(String id, AudioSource source, int s, int e) =>
      segment(id, source, s, LiveTranscriptionService.gapMarkerText(s, e));

  group('décision', () {
    test('la marge vaut une seconde', () {
      expect(GapBackfillService.margin, const Duration(seconds: 1));
    });

    test('sans repère, rien à retranscrire', () {
      expect(
        GapBackfillService.plan(<TranscriptSegmentEntity>[
          segment('a', AudioSource.input, 5000, 'Bonjour.'),
        ]),
        isEmpty,
      );
    });

    test('un repère donne son intervalle élargi de la marge, pour sa '
        'source', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        segment('a', AudioSource.input, 5000, 'Bonjour.'),
        marker('m', AudioSource.output, 10000, 20000),
      ]);

      expect(plan, hasLength(1));
      expect(plan.single.markerId, 'm');
      expect(plan.single.source, AudioSource.output);
      expect(plan.single.startMs, 10000 - margin);
      expect(plan.single.endMs, 20000 + margin);
    });

    test('la marge ne passe pas avant le début de la réunion', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        marker('m', AudioSource.input, 0, 4000),
      ]);

      expect(plan.single.startMs, 0);
    });
  });

  group('service', () {
    late Directory dir;
    late InMemoryTranscriptRepository repo;
    late _FakeTranscriber transcriber;
    bool recording = false;

    /// WAV de 30 s dont chaque chunk de 100 ms porte son numéro + [base].
    Future<void> wav(String suffix, {int base = 0}) async {
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_$suffix.wav');
      for (int id = 0; id < 300; id++) {
        final Uint8List data = Uint8List(3200);
        ByteData.sublistView(data)
          ..setInt16(0, (id + base) & 0x7FFF, Endian.little)
          ..setInt16(2, (id + base) >> 15, Endian.little);
        await recorder.append(data);
      }
      await recorder.close();
    }

    GapBackfillService service() => GapBackfillService(
      transcriber: transcriber,
      transcripts: repo,
      isRecording: () => recording,
    );

    List<TranscriptSegmentEntity> sorted(AudioSource source) =>
        repo.of(source)..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_backfill_');
      repo = InMemoryTranscriptRepository();
      transcriber = _FakeTranscriber();
      recording = false;
      await wav('mic');
      await wav('system', base: 10000);
    });

    tearDown(() => dir.delete(recursive: true));

    test('le repère est remplacé par les phrases retrouvées, à leur '
        'heure', () async {
      for (final TranscriptSegmentEntity s in <TranscriptSegmentEntity>[
        segment('a', AudioSource.input, 5000, 'Avant.'),
        marker('m', AudioSource.input, 10000, 20000),
        segment('b', AudioSource.input, 25000, 'Après.'),
      ]) {
        await repo.save(s);
      }
      transcriber.reply = <({int offsetMs, String text})>[
        (offsetMs: 500, text: 'Bonjour.'),
        (offsetMs: 4000, text: 'Ça va ?'),
      ];

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      final List<TranscriptSegmentEntity> after = sorted(AudioSource.input);
      expect(after.map((s) => s.text), <String>[
        'Avant.',
        'Bonjour.',
        'Ça va ?',
        'Après.',
      ]);
      expect(after.map((s) => s.timestampMs), <int>[
        5000,
        10000 - margin + 500,
        10000 - margin + 4000,
        25000,
      ]);
      expect(after.every((s) => s.sessionId == sessionId), isTrue);
      expect(after.map((s) => s.id).toSet(), hasLength(4));

      // Le bon intervalle du bon WAV : de 9 s à 21 s du micro.
      final Uint8List pcm = transcriber.calls.single;
      expect(pcm.length, (20000 - 10000 + 2 * margin) * 32);
      expect(_idAt(pcm, 0), (10000 - margin) ~/ 100);
    });

    test('un repère du son du Mac lit le WAV système', () async {
      await repo.save(marker('m', AudioSource.output, 3000, 5000));
      transcriber.reply = <({int offsetMs, String text})>[
        (offsetMs: 0, text: 'Client.'),
      ];

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(_idAt(transcriber.calls.single, 0), 10000 + 20);
      expect(sorted(AudioSource.output).map((s) => s.text), <String>[
        'Client.',
      ]);
    });

    test('si la retranscription échoue, le repère reste', () async {
      final TranscriptSegmentEntity m = marker(
        'm',
        AudioSource.input,
        10000,
        20000,
      );
      await repo.save(m);
      transcriber.fails = true;

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(repo.of(AudioSource.input), <TranscriptSegmentEntity>[m]);
    });

    test('rien de retrouvé : le repère reste', () async {
      final TranscriptSegmentEntity m = marker(
        'm',
        AudioSource.input,
        10000,
        20000,
      );
      await repo.save(m);
      transcriber.reply = const <({int offsetMs, String text})>[];

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(repo.of(AudioSource.input), <TranscriptSegmentEntity>[m]);
    });

    test('jamais pendant un enregistrement', () async {
      await repo.save(marker('m', AudioSource.input, 10000, 20000));
      recording = true;

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(transcriber.calls, isEmpty);
      expect(repo.of(AudioSource.input).single.id, 'm');
    });

    test('deux passages donnent le même résultat', () async {
      await repo.save(marker('m', AudioSource.input, 10000, 20000));
      transcriber.reply = <({int offsetMs, String text})>[
        (offsetMs: 500, text: 'Bonjour.'),
      ];

      await service().backfill(sessionId, recordingsDirectory: dir.path);
      final List<String> first = sorted(
        AudioSource.input,
      ).map((s) => s.text).toList();
      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(sorted(AudioSource.input).map((s) => s.text), first);
      expect(transcriber.calls, hasLength(1));
    });

    test('WAV absent (supprimé après la réunion) : le repère reste, sans '
        'erreur', () async {
      final TranscriptSegmentEntity m = marker(
        'm',
        AudioSource.input,
        10000,
        20000,
      );
      await repo.save(m);
      await File('${dir.path}/${sessionId}_mic.wav').delete();

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(transcriber.calls, isEmpty);
      expect(repo.of(AudioSource.input), <TranscriptSegmentEntity>[m]);
    });

    test('une session sans repère ne déclenche rien', () async {
      await repo.save(segment('a', AudioSource.input, 5000, 'Bonjour.'));

      await service().backfill(sessionId, recordingsDirectory: dir.path);

      expect(transcriber.calls, isEmpty);
    });
  });
}

int _idAt(Uint8List pcm, int offset) {
  final ByteData d = ByteData.sublistView(pcm);
  return d.getInt16(offset, Endian.little) +
      (d.getInt16(offset + 2, Endian.little) << 15);
}

final class _FakeTranscriber implements PcmTranscriber {
  final List<Uint8List> calls = <Uint8List>[];
  List<({int offsetMs, String text})> reply =
      const <({int offsetMs, String text})>[];
  bool fails = false;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls.add(Uint8List.fromList(pcm));
    if (fails) throw StateError('serveur de transcription indisponible');
    return reply;
  }
}
