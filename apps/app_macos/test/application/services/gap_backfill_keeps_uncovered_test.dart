import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/probe5_sequences.dart';
import '../../fixtures/probe8_sequences.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart';

// Tour 10, point 2 — le rattrapage ne supprime jamais ce qu'il ne rend pas.
//
// Sonde 8 (Dlag avec rattrapage, son système) : la phrase 11 (« La voisine
// a nettoyé le kiosque à journaux avant la pluie du soir… », audio
// 101,99–108,59 s) est rangée à 111,615 s (`_output_16`, fenêtre de la
// phrase 12). Le plan de 1:49–1:58 (108,1–120,5 s) la remplace par le
// temps ; le vrai serveur n'a rendu, pour cet audio, que la phrase 12 :
// la phrase 11 a disparu de la note, sans repère.
//
// Attendu : un segment remplacé dont le texte n'est pas couvert par le
// texte rattrapé est gardé, ou l'intervalle est élargi jusqu'à son vrai
// audio (le transcripteur factice rend alors les phrases de cet audio).
// De bout en bout, avec les segments enregistrés et un serveur qui ne rend
// que 108–120 s : la phrase 11 est dans la note, une fois ; rien en double.
void main() {
  const String sentence11 =
      'La voisine a nettoyé le kiosque à journaux avant la pluie du soir';

  late List<TranscriptSegmentEntity> lines;

  setUpAll(() async {
    final InMemoryTranscriptRepository repo = await runRecordedBackfill(
      RecordedSession.fromScenario(probe8Dlag),
    );
    lines = repo.of(AudioSource.output)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  });

  test('sonde 8 : la phrase 11, que le rattrapage ne rend pas, reste dans la '
      'note, une fois', () {
    final List<TranscriptSegmentEntity> hits = <TranscriptSegmentEntity>[
      for (final TranscriptSegmentEntity s in lines)
        if (s.text.contains(sentence11)) s,
    ];
    expect(
      hits,
      hasLength(1),
      reason:
          'phrase 11 trouvée ${hits.length} fois ; segments 95–125 s : '
          '${lines.where((s) => s.timestampMs > 95000 && s.timestampMs < 125000).map((s) => '${s.timestampMs} ${s.text.substring(0, 30)}').join(' | ')}',
    );
  });

  test('sonde 8 : aucune phrase de référence en double dans la note', () {
    final List<String> texts = <String>[
      for (final TranscriptSegmentEntity s in lines) words(s.text).join(' '),
    ];
    final List<String> clauses = <String>[
      for (final ProbeSentence r in probeReference)
        if (r.source == 'output') words(r.text.split(',').first).join(' '),
    ];
    final List<String> twice = <String>[
      for (final String c in clauses)
        // Une proposition commune à deux phrases de référence ne compte pas.
        if (clauses.where((String o) => o == c).length == 1 &&
            texts.where((String t) => t.contains(c)).length > 1)
          c,
    ];
    expect(twice, isEmpty, reason: 'en double : $twice');
  });
}
