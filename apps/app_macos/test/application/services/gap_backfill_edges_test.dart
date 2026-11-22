import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 6, point 2 (mesuré deux fois) : le texte direct de la phrase coupée
// par la perte est lui-même abîmé (« La boulangère a » avant un arrêt
// brutal, « Affiez le lavoir… » au bord) ; trimOverlaps n'y trouve aucun
// mot identique et la phrase retrouvée côtoie son double abîmé.
//
// Règle : l'intervalle retranscrit s'étend aux phrases coupées par la
// perte, et ces segments abîmés sont REMPLACÉS par le texte retrouvé.
// - avant : le dernier segment de la source avant le repère, s'il est
//   partiel (`isPartial`) ; l'intervalle part de son heure ;
// - après : le premier segment après le repère s'il commence au bord de la
//   perte (à [GapBackfillService.edgeTolerance] près) ; l'intervalle va
//   jusqu'au segment suivant de la source, ou 30 s après au plus.
// Un voisin complet et éloigné du bord n'est jamais retiré. Idempotent.
//
// API supposée : le plan gagne `replacedIds` (List<String>) ;
// `static const Duration edgeTolerance` (1 s) ; `TranscriptSegmentEntity
// .isPartial`. La marge (`margin`, 1 s) s'applique aux bords de la perte.
void main() {
  const String sessionId = '1700000000000';
  final int margin = GapBackfillService.margin.inMilliseconds;

  TranscriptSegmentEntity seg(
    String id,
    int ts,
    String text, {
    bool partial = false,
    AudioSource source = AudioSource.input,
  }) => TranscriptSegmentEntity(
    id: id,
    sessionId: sessionId,
    source: source,
    text: text,
    timestampMs: ts,
    createdAt: DateTime(2026, 11, 22, 10),
    isPartial: partial,
  );

  TranscriptSegmentEntity marker(String id, int s, int e) =>
      seg(id, s, LiveTranscriptionService.gapMarkerText(s, e));

  group('décision', () {
    test('le bord est d une seconde', () {
      expect(GapBackfillService.edgeTolerance, const Duration(seconds: 1));
    });

    test('arrêt brutal : la phrase partielle avant la perte est remplacée, '
        'l intervalle part de son heure', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        seg('a', 20000, 'Bonjour à tous.'),
        seg('p', 40000, 'La boulangère a', partial: true),
        marker('m', 41000, 60000),
        seg('n', 75000, 'Le pain est chaud.'),
      ]);

      expect(plan, hasLength(1));
      expect(plan.single.replacedIds, <String>['p']);
      expect(plan.single.startMs, 40000 - margin);
      expect(plan.single.endMs, 60000 + margin);
    });

    test('au bord de fin : la phrase qui commence à la fin de la perte est '
        'remplacée, jusqu au segment suivant', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        marker('m', 10000, 20000),
        seg('n', 20200, 'Affiez le lavoir du village.'),
        seg('s', 26000, 'Suite de la réunion.'),
      ]);

      expect(plan.single.replacedIds, <String>['n']);
      expect(plan.single.startMs, 10000 - margin);
      expect(plan.single.endMs, 26000);
    });

    test('au bord de fin sans segment suivant : 30 s au plus', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        marker('m', 10000, 20000),
        seg('n', 20500, 'Affiez le lavoir du village.'),
      ]);

      expect(plan.single.replacedIds, <String>['n']);
      expect(plan.single.endMs, 20500 + 30000);
    });

    test('les voisins complets et loin des bords ne sont jamais remplacés', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        seg('a', 5000, 'Bonjour à tous.'),
        marker('m', 10000, 20000),
        seg('b', 25000, 'On continue.'),
      ]);

      expect(plan.single.replacedIds, isEmpty);
      expect(plan.single.startMs, 10000 - margin);
      expect(plan.single.endMs, 20000 + margin);
    });

    test('un segment partiel d une autre source n est pas touché', () {
      final plan = GapBackfillService.plan(<TranscriptSegmentEntity>[
        seg(
          'o',
          9000,
          'Hello every',
          partial: true,
          source: AudioSource.output,
        ),
        marker('m', 10000, 20000),
      ]);

      expect(plan.single.replacedIds, isEmpty);
    });
  });

  group('service', () {
    late Directory dir;
    late InMemoryTranscriptRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_edges_');
      repo = InMemoryTranscriptRepository();
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_mic.wav');
      await recorder.append(Uint8List(120 * 32000));
      await recorder.close();
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> run(List<({int offsetMs, String text})> reply) =>
        GapBackfillService(
          transcriber: _Reply(reply),
          transcripts: repo,
          isRecording: () => false,
        ).backfill(sessionId, recordingsDirectory: dir.path);

    List<String> texts() =>
        (repo.of(AudioSource.input)
              ..sort((x, y) => x.timestampMs.compareTo(y.timestampMs)))
            .map((TranscriptSegmentEntity s) => s.text)
            .toList();

    test('la phrase abîmée est remplacée par la phrase retrouvée, les '
        'voisins complets restent, et deux passages donnent le même '
        'résultat', () async {
      for (final TranscriptSegmentEntity s in <TranscriptSegmentEntity>[
        seg('a', 20000, 'Bonjour à tous.'),
        seg('p', 40000, 'La boulangère a', partial: true),
        marker('m', 41000, 60000),
        seg('n', 75000, 'Le pain est chaud.'),
      ]) {
        await repo.save(s);
      }
      final List<({int offsetMs, String text})> reply =
          <({int offsetMs, String text})>[
            (offsetMs: 1000, text: 'La boulangère a ouvert à six heures.'),
            (offsetMs: 9000, text: 'Les clients attendaient déjà.'),
          ];

      await run(reply);
      final List<String> once = texts();
      await run(reply);

      expect(once, <String>[
        'Bonjour à tous.',
        'La boulangère a ouvert à six heures.',
        'Les clients attendaient déjà.',
        'Le pain est chaud.',
      ]);
      expect(texts(), once);
    });

    test('la phrase au bord de fin est remplacée', () async {
      for (final TranscriptSegmentEntity s in <TranscriptSegmentEntity>[
        marker('m', 10000, 20000),
        seg('n', 20200, 'Affiez le lavoir du village.'),
        seg('s', 26000, 'Suite de la réunion.'),
      ]) {
        await repo.save(s);
      }

      await run(<({int offsetMs, String text})>[
        (offsetMs: 2000, text: 'Nous parlions du budget.'),
        (offsetMs: 11000, text: 'Faites visiter le lavoir du village.'),
      ]);

      expect(texts(), <String>[
        'Nous parlions du budget.',
        'Faites visiter le lavoir du village.',
        'Suite de la réunion.',
      ]);
    });

    test('rien de retrouvé : la phrase abîmée et le repère restent', () async {
      for (final TranscriptSegmentEntity s in <TranscriptSegmentEntity>[
        seg('p', 40000, 'La boulangère a', partial: true),
        marker('m', 41000, 60000),
      ]) {
        await repo.save(s);
      }

      await run(const <({int offsetMs, String text})>[]);

      expect(texts(), contains('La boulangère a'));
      expect(texts().any((String t) => t.startsWith('Transcription')), isTrue);
    });
  });
}

final class _Reply implements PcmTranscriber {
  _Reply(this.pieces);

  final List<({int offsetMs, String text})> pieces;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      pieces;
}
