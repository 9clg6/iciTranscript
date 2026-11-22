import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 6, point 2 : la phrase en cours sauvée est marquée partielle
// (`TranscriptSegmentEntity.isPartial`), la phrase finale ne l'est plus,
// une phrase scellée par une perte le reste : le rattrapage sait ainsi
// quelles phrases coupées remplacer.
void main() {
  List<TranscriptSegmentEntity> saved(LiveServiceHarness h) =>
      h.segments.of(AudioSource.output);

  group('drapeau partiel (point 2)', () {
    test(
      'la phrase en cours sauvée est partielle, la finale ne l est plus',
      () {
        fakeAsync((FakeAsync async) {
          final LiveServiceHarness h = LiveServiceHarness(async)..start();
          h.fakeRemote.emitDelta(AudioSource.output, 'La boulangère a');
          async.elapse(const Duration(seconds: 5));
          expect(saved(h).single.isPartial, isTrue);

          h.fakeRemote.emitDone(
            AudioSource.output,
            'La boulangère a ouvert à six heures.',
          );
          async.elapse(const Duration(seconds: 1));
          expect(saved(h).single.isPartial, isFalse);
        });
      },
    );

    test('une phrase scellée par une perte reste partielle', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        h.fakeRemote.emitDelta(AudioSource.output, 'La boulangère a');
        async.elapse(const Duration(seconds: 5));

        h.fakeRemote.emitControl(AudioSource.output, utteranceLostEventType);
        async.elapse(const Duration(seconds: 1));

        final TranscriptSegmentEntity sealed = saved(h).singleWhere(
          (TranscriptSegmentEntity s) => s.text == 'La boulangère a',
        );
        expect(sealed.isPartial, isTrue);
      });
    });
  });
}
