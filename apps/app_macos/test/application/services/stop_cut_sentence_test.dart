import 'dart:async';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

// Tour 8, point c : phrase coupée par l'arrêt (vu en réunions enchaînées,
// sonde 6). Le texte partiel dit avant l'arrêt et le texte finalisé ensuite
// ne doivent pas rester tous les deux : une seule phrase, la plus complète,
// à l'heure où la phrase a commencé. Textes enregistrés (réunion B).
void main() {
  const String partial =
      'Le jardinier a repeint la cabane pour la rentrée des classes, puis le '
      'jardinier a nettoyé le kiosque';
  const String full =
      'Le jardinier a repeint la cabane pour la rentrée des classes, puis le '
      'jardinier a nettoyé le kiosque à journaux avant la pluie du soir.';

  /// Phrase en cours (provisoire sauvé), puis arrêt qui attend sa fin ;
  /// [finalText] arrive pendant l'attente.
  List<TranscriptSegmentEntity> stopDuring(FakeAsync async, String finalText) {
    final LiveServiceHarness h = LiveServiceHarness(async)..start();
    async.elapse(const Duration(seconds: 80));
    h.fakeRemote.emitDelta(AudioSource.input, partial);
    async.elapse(const Duration(seconds: 3)); // provisoire en base
    final int startedAt = h.segments.of(AudioSource.input).single.timestampMs;

    h.fakeRemote.active = <AudioSource>{AudioSource.input};
    bool stopped = false;
    unawaited(h.service.stopTranscription().then((_) => stopped = true));
    async.elapse(const Duration(seconds: 2));
    h.fakeRemote.active = <AudioSource>{};
    h.fakeRemote.emitDone(AudioSource.input, finalText);
    for (int i = 0; i < 300 && !stopped; i++) {
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(stopped, isTrue);
    final List<TranscriptSegmentEntity> saved = h.segments.of(
      AudioSource.input,
    );
    expect(saved, hasLength(1), reason: 'une seule phrase');
    expect(saved.single.timestampMs, startedAt, reason: 'heure du début');
    return saved;
  }

  test('le texte final, plus complet, remplace le partiel', () {
    fakeAsync((FakeAsync async) {
      expect(stopDuring(async, full).single.text, full);
    });
  });

  test('un texte final moins complet ne remplace pas le partiel', () {
    fakeAsync((FakeAsync async) {
      expect(
        stopDuring(async, 'Le jardinier a repeint la cabane').single.text,
        partial,
      );
    });
  });
}
