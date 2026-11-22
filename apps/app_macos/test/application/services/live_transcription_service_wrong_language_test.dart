import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 6, point 4a/4b (sonde 4, reproduit 5/5) : le modèle a rendu une
// phrase en écriture hindi, que le filtre non latin a JETÉE sans repère :
// perte silencieuse ; et une autre en espagnol, gardée telle quelle.
// - texte final écarté par le filtre d'écriture alors que la phrase avait
//   de la parole → repère « transcription interrompue » sur l'intervalle de
//   la phrase (rattrapé ensuite) ; sans parole → écarté comme aujourd'hui ;
// - texte final avec parole dans une langue non attendue (contrôle de
//   langue) → même traitement.
void main() {
  UtteranceWindow window(LiveServiceHarness h, int s, int e, bool speech) =>
      UtteranceWindow(startMs: h.t0 + s, endMs: h.t0 + e, hadSpeech: speech);

  List<TranscriptSegmentEntity> saved(LiveServiceHarness h) =>
      h.segments.of(AudioSource.output);

  test('écriture non latine avec parole : un repère sur l intervalle de la '
      'phrase, jamais une perte silencieuse', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(
        AudioSource.output,
        'नमस्ते आप सब कैसे हैं आज',
        window: window(h, 12000, 18000, true),
      );
      async.elapse(const Duration(seconds: 1));

      final TranscriptSegmentEntity marker = saved(h).single;
      expect(marker.text, startsWith('Transcription interrompue'));
      expect(marker.timestampMs, 12000);
      expect(marker.text, matches(RegExp(r'00:00:12\s*[–-]\s*00:00:18')));
    });
  });

  test('écriture non latine sans parole : écartée comme aujourd hui', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(
        AudioSource.output,
        'नमस्ते आप सब कैसे हैं आज',
        window: window(h, 12000, 18000, false),
      );
      async.elapse(const Duration(seconds: 1));

      expect(saved(h), isEmpty);
    });
  });

  test('langue non attendue avec parole : un repère, pas le texte', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(
        AudioSource.output,
        'El equipo ha terminado el presupuesto para el próximo trimestre.',
        window: window(h, 30000, 36000, true),
      );
      async.elapse(const Duration(seconds: 1));

      final TranscriptSegmentEntity marker = saved(h).single;
      expect(marker.text, startsWith('Transcription interrompue'));
      expect(marker.timestampMs, 30000);
    });
  });

  test('une phrase française reste du texte', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      h.fakeRemote.emitDone(
        AudioSource.output,
        'On a parlé avec Gonzalez et Rodriguez de Madrid hier.',
        window: window(h, 30000, 36000, true),
      );
      async.elapse(const Duration(seconds: 1));

      expect(
        saved(h).single.text,
        'On a parlé avec Gonzalez et Rodriguez de Madrid hier.',
      );
    });
  });
}
