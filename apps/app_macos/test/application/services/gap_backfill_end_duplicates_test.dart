import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../fixtures/probe8_sequences.dart';
import '../../fixtures/probe9_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Suivi du tour 10, point 1 — DOUBLONS DE FIN (sonde 9). Le départ du
// rattrapage est ramené au dernier segment intact (2 s après son début) :
// la seconde moitié de cette phrase intacte est retranscrite, et
// `trimOverlaps` ne la retire pas quand un mot diffère ou que le début est
// abîmé. Cas enregistrés : A2 et D au micro (168,9 s) et au système
// (11,0 s, 103,9 s), S06 au système (47,3 s) : un segment à part, ~2 s
// après la phrase complète, qui en répète la fin (« L'Omavois, puis la
// gardienne… », « Dans la pluie de soir, puis le maire… », « Elbri, puis
// la gardienne… »).
//
// Rejoués avec les textes rattrapés enregistrés. Attendu : chaque phrase
// une fois ; aucun fragment ne répète la fin de la phrase intacte qui le
// précède ; la phrase 11 de la sonde 8 revient toujours. Mécanisme libre :
// départ au premier silence entre phrases après le début du segment intact
// (le banc rend alors les morceaux qui commencent dans l'audio demandé), ou
// coupe tolérante d'un premier morceau qui n'est presque que la fin du
// voisin intact (le banc rend alors les morceaux enregistrés).
//
// « Répète la fin » : au moins 60 % des mots du fragment, dans l'ordre,
// dans la ligne intacte qui le précède (les fragments enregistrés valent
// 0,8 à 0,9 ; deux phrases voisines, de langues alternées, moins de 0,3).
const double _repeats = 0.6;

final Map<String, RecordedSession> _cases = <String, RecordedSession>{
  'A2': RecordedSession.fromScenario(probe9A2),
  'D': RecordedSession.fromScenario(probe9D),
  'S06': RecordedSession.fromScenario(
    probe9S06,
    reference: probe9Live60Reference,
  ),
};

/// Heures (ms) des doublons enregistrés, par cas et source.
const Map<String, List<(AudioSource, int)>> _recorded =
    <String, List<(AudioSource, int)>>{
      'A2': <(AudioSource, int)>[
        (AudioSource.input, 168917),
        (AudioSource.output, 11017),
        (AudioSource.output, 103917),
      ],
      'D': <(AudioSource, int)>[
        (AudioSource.input, 168919),
        (AudioSource.output, 11019),
        (AudioSource.output, 103919),
      ],
      'S06': <(AudioSource, int)>[(AudioSource.output, 47252)],
    };

bool _isMarkerSegment(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) ||
    LiveTranscriptionService.isUntranscribedMarker(s.text);

List<TranscriptSegmentEntity> _lines(
  InMemoryTranscriptRepository repo,
  AudioSource source,
) =>
    repo
        .of(source)
        .where((TranscriptSegmentEntity s) => !_isMarkerSegment(s))
        .toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

/// Lignes qui répètent la fin de la ligne qui les précède.
List<String> _tailRepeats(List<TranscriptSegmentEntity> lines) => <String>[
  for (int i = 1; i < lines.length; i++)
    if (lines[i].timestampMs - lines[i - 1].timestampMs < 15000 &&
        coverage(lines[i].text, lines[i - 1].text) >= _repeats)
      '${lines[i].timestampMs} « ${lines[i].text} » répète '
          '${lines[i - 1].timestampMs} « ${lines[i - 1].text} »',
];

void main() {
  test('les fragments enregistrés répètent bien la fin de leur voisin (le '
      'critère les voit)', () {
    for (final MapEntry<String, List<(AudioSource, int)>> c
        in _recorded.entries) {
      final ProbeScenario sc = switch (c.key) {
        'A2' => probe9A2,
        'D' => probe9D,
        _ => probe9S06,
      };
      for (final (AudioSource source, int atMs) in c.value) {
        final ProbeGap g = sc.gaps.firstWhere(
          (ProbeGap g) => sourceOf(g.source) == source && g.planStartMs == atMs,
        );
        final String fragment = g.recovered.first.text;
        final ProbeSegment intact = sc.segments
            .where(
              (ProbeSegment s) =>
                  sourceOf(s.source) == source && s.timestampMs < atMs,
            )
            .reduce(
              (ProbeSegment a, ProbeSegment b) =>
                  a.timestampMs > b.timestampMs ? a : b,
            );
        expect(
          coverage(fragment, intact.text),
          greaterThanOrEqualTo(_repeats),
          reason: '${c.key} $atMs « $fragment »',
        );
      }
    }
  });

  for (final MapEntry<String, RecordedSession> c in _cases.entries) {
    test('${c.key} (sonde 9) : aucun fragment ne répète la fin de la phrase '
        'intacte qui le précède', () async {
      final InMemoryTranscriptRepository repo = await runRecordedBackfill(
        c.value,
      );
      final List<String> repeats = <String>[
        for (final AudioSource source in c.value.sources)
          ..._tailRepeats(_lines(repo, source)),
      ];
      expect(repeats, isEmpty, reason: repeats.join('\n'));
    });

    test(
      '${c.key} (sonde 9) : chaque phrase de référence au plus une fois',
      () async {
        final InMemoryTranscriptRepository repo = await runRecordedBackfill(
          c.value,
        );
        final List<String> twice = <String>[];
        for (final AudioSource source in c.value.sources) {
          final List<String> texts = <String>[
            for (final TranscriptSegmentEntity s in _lines(repo, source))
              words(s.text).join(' '),
          ];
          final List<String> clauses = <String>[
            for (final ProbeSentence r in c.value.reference)
              if (sourceOf(r.source) == source && r.endMs <= c.value.endMs)
                words(r.text.split(',').first).join(' '),
          ];
          for (final String clause in clauses) {
            if (clauses.where((String o) => o == clause).length > 1) continue;
            if (texts.where((String t) => t.contains(clause)).length > 1) {
              twice.add('${source.name} « $clause »');
            }
          }
        }
        expect(twice, isEmpty, reason: twice.join('\n'));
      },
    );
  }

  test('sonde 8 : la phrase 11 revient toujours, une fois', () async {
    final InMemoryTranscriptRepository repo = await runRecordedBackfill(
      RecordedSession.fromScenario(probe8Dlag),
    );
    expect(
      _lines(repo, AudioSource.output).where(
        (TranscriptSegmentEntity s) => s.text.contains(
          'La voisine a nettoyé le kiosque à journaux avant la pluie du soir',
        ),
      ),
      hasLength(1),
    );
    expect(_tailRepeats(_lines(repo, AudioSource.output)), isEmpty);
  });

  group('gardes : ce qui ne fait que RESSEMBLER à la fin du voisin reste', () {
    // Phrase intacte P (9,0–15,6 s) ; perte 18–40 s. La phrase suivante N
    // (17,0 s) commence par les mêmes mots que la fin de P puis dit autre
    // chose ; M (24,5 s) est sans rapport. Le vrai rattrapage (départ 11 s)
    // a rendu : la fin abîmée de P, N, M.
    const String sessionId = 'garde';
    const String intact =
        'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la '
        'gardienne a réparé la vieille barrière pour la rentrée des classes.';
    const String lookalike =
        'Puis la gardienne a réparé la vieille barrière, et le maire a '
        'repeint le portail vert au lever du soleil.';
    const String unrelated =
        'The librarian tidied the small cabin with a lot of patience.';
    const List<ProbeSentence> reference = <ProbeSentence>[
      (source: 'output', startMs: 9000, endMs: 15600, text: intact),
      (source: 'output', startMs: 17000, endMs: 23000, text: lookalike),
      (source: 'output', startMs: 24500, endMs: 30000, text: unrelated),
    ];

    RecordedSession session(
      List<RecoveredPiece> recovered, {
      int recordedEndMs = 41000,
    }) => RecordedSession(
      name: 'garde',
      sessionId: sessionId,
      reference: reference,
      stored: <TranscriptSegmentEntity>[
        TranscriptSegmentEntity(
          id: '${sessionId}_output_1',
          sessionId: sessionId,
          source: AudioSource.output,
          text: intact,
          timestampMs: 9000,
          createdAt: DateTime(2026, 11, 24),
        ),
        TranscriptSegmentEntity(
          id: '${sessionId}_output_2',
          sessionId: sessionId,
          source: AudioSource.output,
          text: LiveTranscriptionService.gapMarkerText(18000, 40000),
          timestampMs: 18000,
          createdAt: DateTime(2026, 11, 24),
        ),
      ],
      recovered: recovered,
      recordedStarts: <RecordedInterval>[
        (source: 'output', startMs: 11000, endMs: recordedEndMs),
      ],
    );

    test('une phrase nouvelle qui commence comme la fin du voisin est '
        'gardée', () async {
      final InMemoryTranscriptRepository repo = await runRecordedBackfill(
        session(<RecoveredPiece>[
          (
            source: 'output',
            fromMs: 11000,
            atMs: 11000,
            text:
                "L'Omavois, puis la gardienne a réparé la vieille barrière "
                'pour la rentrée des classes.',
          ),
          (source: 'output', fromMs: 11000, atMs: 17000, text: lookalike),
          (source: 'output', fromMs: 11000, atMs: 24500, text: unrelated),
        ]),
      );
      final String note = _lines(
        repo,
        AudioSource.output,
      ).map((TranscriptSegmentEntity s) => s.text).join(' ');
      expect(note, contains('le maire a repeint le portail vert au lever'));
      expect(note, contains('tidied the small cabin'));
      expect(_tailRepeats(_lines(repo, AudioSource.output)), isEmpty);
    });

    test('un premier morceau qui reprend la fin du voisin PUIS dit autre '
        'chose garde ces mots nouveaux', () async {
      final InMemoryTranscriptRepository repo = await runRecordedBackfill(
        session(<RecoveredPiece>[
          (
            source: 'output',
            fromMs: 11000,
            atMs: 11000,
            text:
                'Pour la rentrée des classes. Puis la gardienne a réparé la '
                'vieille barrière, et le maire a repeint le portail vert au '
                'lever du soleil.',
          ),
          (source: 'output', fromMs: 11000, atMs: 24500, text: unrelated),
          // Un seul morceau couvre 11–23 s : un départ plus tardif n'est pas
          // rejouable, le banc rend alors ce qui est lu dans l'audio demandé.
        ], recordedEndMs: 11001),
      );
      final String note = _lines(
        repo,
        AudioSource.output,
      ).map((TranscriptSegmentEntity s) => s.text).join(' ');
      expect(note, contains('le maire a repeint le portail vert au lever'));
      expect(note, contains('tidied the small cabin'));
    });
  });
}
