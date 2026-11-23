import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../fixtures/probe8_sequences.dart';
import '../../fixtures/probe9_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Tour 10, point 3 — invariant sur toutes les séquences enregistrées
// (sondes 5, 7, 8, 9). Après le direct et le rattrapage, chaque phrase de
// référence finie avant la fin de la session apparaît au moins une fois
// dans la note OU son intervalle est couvert par un repère — jamais ni
// l'un ni l'autre.
//
// « Apparaît » : au moins 60 % de ses mots, dans l'ordre, dans les lignes
// de sa source qui commencent entre 10 s avant elle et 2 s après sa fin
// (une phrase rattrapée est souvent coupée en deux morceaux). Calibrage
// sur ces séquences : la pire transcription correcte (accent, langue
// parasite) atteint 0,76 ; les phrases voisines alternent anglais et
// français et ne dépassent pas 0,6 (vérifié ci-dessous) ; les vraies
// pertes valent 0,00 (sonde 8, phrase 11) et 0,22 (sonde 5 D, micro
// 73,05 s : le segment abîmé « Grafie et le lavoir sous un ciel gris,
// puis la voisine a pho… » est remplacé, le rattrapage ne rend que « Le
// jardinier a photographié le lac. »).
// « Couvert » : un repère (perte ou passage non transcrit) qui commence au
// plus 1 s après elle et finit au plus 1 s avant sa fin.
const double _seen = 0.6;

final List<RecordedSession> _sessions = <RecordedSession>[
  RecordedSession.fromScenario(probeD),
  RecordedSession.fromScenario(probeRelaunch),
  RecordedSession.fromScenario(probeBackToBack),
  RecordedSession.probe7(),
  RecordedSession.fromScenario(probe8Dlag),
  RecordedSession.fromScenario(probe9A2),
  RecordedSession.fromScenario(probe9D),
  RecordedSession.fromScenario(probe9S06, reference: probe9Live60Reference),
];

void main() {
  test('le critère ne voit pas une phrase dans ses voisines', () {
    for (final (String source, List<ProbeSentence> all)
        in <(String, List<ProbeSentence>)>[
          ('input', probeReference),
          ('output', probeReference),
          ('input', probe9Live60Reference),
          ('output', probe9Live60Reference),
        ]) {
      final List<ProbeSentence> refs = all
          .where((ProbeSentence r) => r.source == source)
          .toList();
      for (int i = 1; i + 1 < refs.length; i++) {
        expect(
          coverage(refs[i].text, '${refs[i - 1].text} ${refs[i + 1].text}'),
          lessThan(_seen),
          reason: '$source ${refs[i].startMs}',
        );
      }
    }
  });

  for (final RecordedSession session in _sessions) {
    test('${session.name} : chaque phrase est dans la note ou sous un '
        'repère, jamais ni l un ni l autre', () async {
      final InMemoryTranscriptRepository repo = await runRecordedBackfill(
        session,
      );
      final List<String> neither = <String>[];
      for (final AudioSource src in session.sources) {
        final List<TranscriptSegmentEntity> lines = repo.of(src)
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
        for (final ProbeSentence r in session.reference.where(
          (ProbeSentence r) =>
              sourceOf(r.source) == src && r.endMs <= session.endMs,
        )) {
          final String around = lines
              .where(
                (TranscriptSegmentEntity l) =>
                    !isMarker(l.text) &&
                    l.timestampMs >= r.startMs - 10000 &&
                    l.timestampMs <= r.endMs + 2000,
              )
              .map((TranscriptSegmentEntity l) => l.text)
              .join(' ');
          final bool seen = coverage(r.text, around) >= _seen;
          final bool covered = lines.any((TranscriptSegmentEntity l) {
            final ({int startMs, int endMs})? m = markerRange(l.text);
            return m != null &&
                m.startMs <= r.startMs + 1000 &&
                m.endMs >= r.endMs - 1000;
          });
          if (!seen && !covered) {
            neither.add('${src.name} ${r.startMs} ms « ${r.text} »');
          }
        }
      }
      expect(neither, isEmpty, reason: neither.join('\n'));
    });
  }
}
