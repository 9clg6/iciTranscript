import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/transcript_formatter.dart';
import 'package:ici_transcript/application/services/transcript_text_normalizer.dart';

void main() {
  group('TranscriptTextNormalizer', () {
    test('corrige une longue suite de mots séparés par des points', () {
      expect(
        TranscriptTextNormalizer.normalize(
          'des.textes.qui.sont.écrits.comme.ça.',
        ),
        'des textes qui sont écrits comme ça.',
      );
    });

    test('préserve domaines, versions et ponctuation normale', () {
      expect(
        TranscriptTextNormalizer.normalize(
          'Voir example.com en v1.2.3. Tout va bien.',
        ),
        'Voir example.com en v1.2.3. Tout va bien.',
      );
    });
  });

  group('TranscriptFormatter', () {
    test('exporte la source et le timestamp de chaque piste', () {
      final TranscriptSegmentEntity me = _segment(
        source: AudioSource.input,
        timestampMs: 3723000,
        text: 'Bonjour',
      );
      final TranscriptSegmentEntity meeting = _segment(
        source: AudioSource.output,
        timestampMs: 65000,
        text: 'Bonjour à vous',
      );

      expect(TranscriptFormatter.plainLine(me), '[01:02:03] MOI: Bonjour');
      expect(
        TranscriptFormatter.markdownLine(meeting),
        '**[00:01:05] RÉUNION** — Bonjour à vous',
      );
    });
  });
}

TranscriptSegmentEntity _segment({
  required AudioSource source,
  required int timestampMs,
  required String text,
}) => TranscriptSegmentEntity(
  id: '${source.name}-$timestampMs',
  sessionId: 'session',
  source: source,
  text: text,
  timestampMs: timestampMs,
  createdAt: DateTime(2026),
);
