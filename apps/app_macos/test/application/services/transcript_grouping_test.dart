import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';

TranscriptSegmentEntity _seg(
  String id,
  String text,
  int t, {
  AudioSource source = AudioSource.output,
}) => TranscriptSegmentEntity(
  id: id,
  sessionId: 's',
  source: source,
  text: text,
  timestampMs: t,
  createdAt: DateTime(2026),
);

void main() {
  test('recolle une phrase coupée par une pause', () {
    final List<TranscriptBlock> blocks = groupTranscript(<TranscriptSegmentEntity>[
      _seg('a', 'Maybe I will change my mind', 0),
      _seg('b', 'in one month or two.', 3000),
      _seg('c', 'Okay.', 6000),
    ], speakerLabels: <String, int>{'a': 0, 'b': 0, 'c': 0});
    expect(blocks.map((TranscriptBlock b) => b.segment.text), <String>[
      'Maybe I will change my mind in one month or two.',
      'Okay.',
    ]);
    expect(blocks.first.segmentIds, <String>['a', 'b']);
    expect(blocks.first.segment.timestampMs, 0);
    expect(blocks.first.speaker, 0);
  });

  test('ne mélange ni les sources ni les interlocuteurs', () {
    final List<TranscriptBlock> blocks = groupTranscript(<TranscriptSegmentEntity>[
      _seg('a', 'so we', 0),
      _seg('b', 'agree', 1000, source: AudioSource.input),
      _seg('c', 'and then', 2000),
      _seg('d', 'we ship', 3000),
    ], speakerLabels: <String, int>{'c': 0, 'd': 1});
    expect(blocks.length, 4);
  });

  test('écarte une phrase écrite dans un autre alphabet', () {
    expect(TranscriptTextNormalizer.isForeignScript('Наберегущую'), isTrue);
    expect(TranscriptTextNormalizer.isForeignScript("Ça marche, c'est réglé."), isFalse);
    expect(TranscriptTextNormalizer.isForeignScript('42 %'), isFalse);
  });
}
