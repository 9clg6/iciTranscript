import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/voiced_pcm.dart';

// Tour 7, point 1. Sonde 5 : la règle des bords du tour 6 n'a rien remplacé
// (`replacedIds` vide) : le segment partiel sauvé DANS la perte (57,0 s pour
// un repère à 56 s) n'était ni le voisin d'avant ni le bord de fin ; « La
// gardienne a rangé la cabane… » restait en double, et la phrase abîmée du
// bord de fin (« Grafie et le lavoir… », « In the green bench… ») restait.
//
// Règle PAR LE TEMPS : tout segment de la source de la perte dont le début
// tombe dans [début − tolérance, fin + tolérance] est remplacé par le texte
// rattrapé, quel que soit son texte ou son état. L'autre source et les
// segments hors de cette fenêtre ne sont jamais touchés.
//
// Tolérance : 2 s ([GapBackfillService.edgeTolerance]). Sur les séquences
// enregistrées, le segment coupé commence au plus 1,2 s après le début de la
// perte (le texte arrive ~1 s après l'audio) et la phrase abîmée du bord de
// fin commence 1 s AVANT la fin ; le plus proche segment correct est à
// 8,7 s avant le début et 4,7 s après la fin. 2 s couvre une phrase coupée
// commencée juste avant la perte sans toucher ces voisins. Aucune phrase
// correcte ne tombe dans une fenêtre sur ces trois séquences.
//
// API supposée : le plan gagne `replacedIds` (List<String>) ;
// `static const Duration edgeTolerance` ; pas de changement de schéma.
// Fixtures : séquences réelles (test/fixtures/probe5_sequences.dart).
const List<ProbeScenario> _scenarios = <ProbeScenario>[
  probeD,
  probeRelaunch,
  probeBackToBack,
];

/// Segments retirés par le rattrapage, d'après les séquences enregistrées.
const Map<String, List<String>> _expectedReplaced = <String, List<String>>{
  '1795385073459_input_15': <String>[
    '1795385073459_input_14',
    '1795385073459_input_16',
  ],
  '1795385073459_output_18': <String>[
    '1795385073459_output_13',
    '1795385073459_output_21',
  ],
  '1795385499416_input_pending': <String>['1795385499416_input_10'],
  '1795385499416_output_pending': <String>['1795385499416_output_9'],
  '1795385632867_input_15': <String>['1795385632867_input_14'],
  '1795385632867_output_16': <String>['1795385632867_output_13'],
};

AudioSource _source(String s) =>
    s == 'input' ? AudioSource.input : AudioSource.output;

List<TranscriptSegmentEntity> _before(ProbeScenario sc) =>
    <TranscriptSegmentEntity>[
      for (final ProbeSegment s in sc.segments)
        TranscriptSegmentEntity(
          id: s.id,
          sessionId: sc.sessionId,
          source: _source(s.source),
          text: s.text,
          timestampMs: s.timestampMs,
          createdAt: DateTime(2026, 11, 23),
        ),
      for (final ProbeGap g in sc.gaps)
        TranscriptSegmentEntity(
          id: g.markerId,
          sessionId: sc.sessionId,
          source: _source(g.source),
          text: LiveTranscriptionService.gapMarkerText(
            g.markerStartMs,
            g.markerEndMs,
          ),
          timestampMs: g.markerStartMs,
          createdAt: DateTime(2026, 11, 23),
        ),
    ];

String _norm(String t) => t
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  test('la tolérance des bords est de 2 s', () {
    expect(GapBackfillService.edgeTolerance, const Duration(seconds: 2));
  });

  group('décision sur les séquences enregistrées', () {
    for (final ProbeScenario sc in _scenarios) {
      test('${sc.name} : remplace les segments de la source dans la fenêtre '
          'de la perte, rien d autre', () {
        final plan = GapBackfillService.plan(_before(sc));
        expect(plan, hasLength(sc.gaps.length));
        for (final ProbeGap g in sc.gaps) {
          final replaced = plan
              .where((p) => p.markerId == g.markerId)
              .expand((p) => p.replacedIds)
              .toSet();
          expect(
            replaced,
            _expectedReplaced[g.markerId]!.toSet(),
            reason: g.markerId,
          );
        }
      });
    }
  });

  group('rattrapage sur les séquences enregistrées', () {
    late Directory dir;
    late InMemoryTranscriptRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_time_edges_');
      repo = InMemoryTranscriptRepository();
    });

    tearDown(() => dir.delete(recursive: true));

    /// WAV de la source : chaque échantillon vaut [tag] (1 micro, 2 système),
    /// pour que le transcripteur factice sache quelle perte il retranscrit.
    Future<void> wav(String sessionId, String track, int tag, int ms) async {
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_$track.wav');
      final Uint8List block = voicedPcm(32000, value: tag);
      for (int s = 0; s < ms ~/ 1000; s++) {
        await recorder.append(block);
      }
      await recorder.close();
    }

    Future<void> runOn(ProbeScenario sc) async {
      final int length =
          sc.gaps
              .map((ProbeGap g) => g.markerEndMs)
              .reduce((int a, int b) => a > b ? a : b) +
          40000;
      await wav(sc.sessionId, 'mic', 1, length);
      await wav(sc.sessionId, 'system', 2, length);
      for (final TranscriptSegmentEntity s in _before(sc)) {
        await repo.save(s);
      }
    }

    Future<void> backfill(ProbeScenario sc) => GapBackfillService(
      transcriber: _Recorded(sc),
      transcripts: repo,
      isRecording: () => false,
    ).backfill(sc.sessionId, recordingsDirectory: dir.path);

    List<TranscriptSegmentEntity> of(AudioSource source) =>
        repo.of(source)..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    for (final ProbeScenario sc in _scenarios) {
      test('${sc.name} : chaque phrase de référence au plus une fois, dans '
          'l ordre ; segments hors fenêtre intacts ; idempotent', () async {
        await runOn(sc);
        final Set<String> replaced = <String>{
          for (final ProbeGap g in sc.gaps) ..._expectedReplaced[g.markerId]!,
        };
        final Map<String, TranscriptSegmentEntity> untouched =
            <String, TranscriptSegmentEntity>{
              for (final TranscriptSegmentEntity s in _before(sc))
                if (!replaced.contains(s.id) &&
                    !sc.gaps.any((ProbeGap g) => g.markerId == s.id))
                  s.id: s,
            };

        await backfill(sc);
        final Map<AudioSource, List<String>> once = <AudioSource, List<String>>{
          for (final AudioSource src in AudioSource.values)
            src: of(src).map((TranscriptSegmentEntity s) => s.text).toList(),
        };

        for (final String id in replaced) {
          expect(repo.store.containsKey(id), isFalse, reason: '$id remplacé');
        }
        untouched.forEach((String id, TranscriptSegmentEntity s) {
          expect(repo.store[id], s, reason: '$id hors fenêtre, intact');
        });

        for (final AudioSource src in AudioSource.values) {
          final List<String> texts = once[src]!.map(_norm).toList();
          int lastIndex = -1;
          for (final ProbeSentence ref in probeReference.where(
            (ProbeSentence r) => _source(r.source) == src,
          )) {
            final String clause = _norm(ref.text.split(',').first);
            final List<int> hits = <int>[
              for (int i = 0; i < texts.length; i++)
                for (final Match _ in RegExp(
                  RegExp.escape(clause),
                ).allMatches(texts[i]))
                  i,
            ];
            expect(
              hits.length,
              lessThanOrEqualTo(1),
              reason: '${src.name} : « $clause » en double',
            );
            if (hits.isNotEmpty) {
              expect(
                hits.single,
                greaterThanOrEqualTo(lastIndex),
                reason: '${src.name} : « $clause » hors d ordre',
              );
              lastIndex = hits.single;
            }
          }
        }

        await backfill(sc);
        for (final AudioSource src in AudioSource.values) {
          expect(
            of(src).map((TranscriptSegmentEntity s) => s.text).toList(),
            once[src],
            reason: 'idempotent',
          );
        }
      });
    }
  });
}

/// Rend, pour chaque perte, le texte que le vrai serveur a rendu (sonde 5),
/// choisi par la source du PCM reçu.
final class _Recorded implements PcmTranscriber {
  _Recorded(this.scenario);

  final ProbeScenario scenario;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final int tag = voicedValue(pcm);
    final String source = tag == 1 ? 'input' : 'output';
    return scenario.gaps
        .firstWhere((ProbeGap g) => g.source == source)
        .recovered;
  }
}
