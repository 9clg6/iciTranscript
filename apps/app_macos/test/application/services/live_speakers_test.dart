import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';

TranscriptSegmentEntity _segment(String id, AudioSource source, int ms, String text) =>
    TranscriptSegmentEntity(
      id: id,
      sessionId: 's',
      source: source,
      text: text,
      timestampMs: ms,
      createdAt: DateTime(2026),
    );

void main() {
  test('fusionne les phrases consécutives d’un même interlocuteur', () {
    final List<TranscriptSegmentEntity> segments = <TranscriptSegmentEntity>[
      _segment('c', AudioSource.output, 9000, 'Et moi Bob.'),
      _segment('a', AudioSource.output, 1000, 'Bonjour.'),
      _segment('me', AudioSource.input, 2000, 'Salut !'),
      _segment('b', AudioSource.output, 4000, 'Je suis Alice.'),
      _segment('x', AudioSource.output, 12000, 'Sans étiquette.'),
    ];
    final List<SpeakerTurn> turns = buildSpeakerTurns(
      segments,
      <String, int>{'a': 0, 'b': 0, 'c': 1, 'me': 3},
    );
    expect(
      turns.map((SpeakerTurn t) => (t.speaker, t.text, t.start, t.end)),
      <(int, String, double, double)>[
        (0, 'Bonjour. Je suis Alice.', 1.0, 4.0),
        (1, 'Et moi Bob.', 9.0, 9.0),
      ],
    );
  });

  test('aucune étiquette, aucun tour', () {
    expect(
      buildSpeakerTurns(<TranscriptSegmentEntity>[
        _segment('a', AudioSource.output, 0, 'x'),
      ], <String, int>{}),
      isEmpty,
    );
  });
}
