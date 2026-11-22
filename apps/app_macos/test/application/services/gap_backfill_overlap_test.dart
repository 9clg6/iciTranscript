import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 5 bis, point 1 (mesuré sur le vrai serveur) : la marge de 1 s
// retranscrit le début de la phrase qui suit la perte (« Le jardinier a
// photographié le lac… »), qui apparaissait deux fois. Les morceaux
// retrouvés ne répètent jamais le texte des segments en direct voisins de la
// même source : les mots qui recouvrent la fin du segment précédent (début
// du premier morceau) ou le début du suivant (fin du dernier morceau) sont
// retirés, sans tenir compte de la casse ni de la ponctuation. Un morceau
// vidé est écarté. Un mot seulement en partie commun (« lac » / « lacune »)
// n'est pas retiré. La marge reste.
//
// API supposée : `static List<({int offsetMs, String text})>
// GapBackfillService.trimOverlaps(List<({int offsetMs, String text})>
// pieces, {String? before, String? after})`, appliquée par `backfill` avec
// le segment non-repère qui précède et celui qui suit le repère.
void main() {
  List<String> trim(List<String> pieces, {String? before, String? after}) =>
      GapBackfillService.trimOverlaps(
        <({int offsetMs, String text})>[
          for (int i = 0; i < pieces.length; i++)
            (offsetMs: i * 5000, text: pieces[i]),
        ],
        before: before,
        after: after,
      ).map((p) => p.text).toList();

  group('décision', () {
    test(
      'cas mesuré : la tête de la phrase suivante est retirée de la fin',
      () {
        expect(
          trim(<String>[
            'Nous avons fini le budget.',
            'Le jardinier a photographié le lac',
          ], after: 'Le jardinier a photographié le lac au lever du jour.'),
          <String>['Nous avons fini le budget.'],
        );
      },
    );

    test('la fin du segment précédent est retirée du début, sans tenir '
        'compte de la casse ni de la ponctuation', () {
      expect(
        trim(<String>[
          'On commence ! Voici le point budget.',
        ], before: 'Bonjour à tous, on commence.'),
        <String>['Voici le point budget.'],
      );
    });

    test('en anglais, aux deux bords d un même morceau', () {
      expect(
        trim(
          <String>['next week. Then we talk money. Okay. The budget review'],
          before: 'We will ship it next week.',
          after: 'The budget review is due Friday.',
        ),
        <String>['Then we talk money. Okay.'],
      );
    });

    test('un morceau entièrement répété est écarté', () {
      expect(
        trim(<String>[
          'Voici le point.',
          'Le jardinier a',
        ], after: 'Le jardinier a photographié le lac.'),
        <String>['Voici le point.'],
      );
    });

    test('un mot seulement en partie commun n est pas retiré', () {
      expect(
        trim(<String>['lacune dans le plan.'], before: 'On a vu le lac.'),
        <String>['lacune dans le plan.'],
      );
      expect(
        trim(<String>['We kept testing'], after: 'Test results are green.'),
        <String>['We kept testing'],
      );
    });

    test('les morceaux du milieu ne sont pas touchés, sans voisin rien ne '
        'change', () {
      expect(
        trim(
          <String>['Le lac.', 'Le lac.', 'Fin.'],
          before: 'Le lac.',
          after: 'Fin.',
        ),
        <String>['Le lac.'],
      );
      expect(trim(<String>['Bonjour.', 'Au revoir.']), <String>[
        'Bonjour.',
        'Au revoir.',
      ]);
    });

    test('les heures des morceaux gardés ne changent pas', () {
      final List<({int offsetMs, String text})> out =
          GapBackfillService.trimOverlaps(<({int offsetMs, String text})>[
            (offsetMs: 0, text: 'on commence. Voici.'),
            (offsetMs: 4000, text: 'Suite.'),
          ], before: 'Bonjour, on commence.');
      expect(out.map((p) => p.offsetMs), <int>[0, 4000]);
    });
  });

  test('le rattrapage ne double pas le texte des segments voisins', () async {
    const String sessionId = '1700000000000';
    final Directory dir = await Directory.systemTemp.createTemp('oats_trim_');
    addTearDown(() => dir.delete(recursive: true));
    final WavRecorder recorder = WavRecorder();
    await recorder.open('${dir.path}/${sessionId}_mic.wav');
    await recorder.append(Uint8List(30 * 32000));
    await recorder.close();

    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    TranscriptSegmentEntity seg(String id, int ts, String text) =>
        TranscriptSegmentEntity(
          id: id,
          sessionId: sessionId,
          source: AudioSource.input,
          text: text,
          timestampMs: ts,
          createdAt: DateTime(2026, 11, 22, 10),
        );
    await repo.save(seg('a', 5000, 'Bonjour à tous, on commence.'));
    await repo.save(
      seg('m', 10000, LiveTranscriptionService.gapMarkerText(10000, 20000)),
    );
    await repo.save(
      seg('b', 20000, 'Le jardinier a photographié le lac au lever du jour.'),
    );

    await GapBackfillService(
      transcriber: _Reply(<({int offsetMs, String text})>[
        (offsetMs: 0, text: 'on commence. Voici le point budget.'),
        (offsetMs: 9000, text: 'Le jardinier a photographié le lac'),
      ]),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(sessionId, recordingsDirectory: dir.path);

    final List<TranscriptSegmentEntity> after = repo.of(AudioSource.input)
      ..sort((x, y) => x.timestampMs.compareTo(y.timestampMs));
    expect(after.map((s) => s.text), <String>[
      'Bonjour à tous, on commence.',
      'Voici le point budget.',
      'Le jardinier a photographié le lac au lever du jour.',
    ]);
  });
}

final class _Reply implements PcmTranscriber {
  _Reply(this.pieces);

  final List<({int offsetMs, String text})> pieces;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      pieces;
}
