import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart' show markerRange;

// Tour 10, point 5 — le flux affiché après une fusion de repères. À CHAQUE
// émission de `segmentsStream` qui suit la fusion, la liste contient
// exactement un repère pour l'union ; un repère absorbé n'y revient jamais
// (ni par `_sortAndDedupeSegments`, ni par les mises à jour du repère
// provisoire, ni par une phrase qui arrive ensuite).
void main() {
  bool isGapMarker(TranscriptSegmentEntity s) =>
      s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

  /// Repères de [source] listés dans [list] qui recoupent [from, to] (ms de
  /// réunion, à la seconde près).
  List<TranscriptSegmentEntity> markersIn(
    List<TranscriptSegmentEntity> list,
    AudioSource source,
    int from,
    int to,
  ) => <TranscriptSegmentEntity>[
    for (final TranscriptSegmentEntity s in list)
      if (s.source == source && isGapMarker(s))
        if (markerRange(s.text) case final ({int startMs, int endMs}) r
            when r.startMs <= to && from <= r.endMs)
          s,
  ];

  test('séquence de la sonde 7 : chaque émission après l union liste un seul '
      'repère pour 1:51–2:35, jamais un absorbé', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = LiveServiceHarness(async)..start();
      async.elapse(const Duration(seconds: 348));
      final List<List<TranscriptSegmentEntity>> emissions =
          <List<TranscriptSegmentEntity>>[];
      final StreamSubscription<List<TranscriptSegmentEntity>> sub = h
          .transcription
          .segmentsStream
          .listen(emissions.add);
      addTearDown(sub.cancel);

      void gap(int startMs, int endMs) => h.fakeRemote.emitGap(
        AudioGap(
          source: AudioSource.output,
          startMs: h.t0 + startMs,
          endMs: h.t0 + endMs,
        ),
      );
      gap(118530, 124000); // 00:01:58 – 00:02:04
      gap(132830, 134000); // 00:02:12 – 00:02:14
      gap(111630, 155000); // 00:01:51 – 00:02:35
      async.elapse(const Duration(seconds: 1));
      // Des phrases arrivent ensuite (tri et dédoublonnage à chaque fois).
      for (int i = 0; i < 10; i++) {
        final int at = 349000 + i * 2000;
        h.fakeRemote.emitDone(
          AudioSource.output,
          'Phrase $i après la fusion.',
          window: UtteranceWindow(
            startMs: h.t0 + at,
            endMs: h.t0 + at + 1500,
            hadSpeech: true,
          ),
        );
        async.elapse(const Duration(seconds: 2));
      }

      final TranscriptSegmentEntity union = h.segments
          .of(AudioSource.output)
          .where(isGapMarker)
          .single;
      final Set<String> absorbed = <String>{
        for (final List<TranscriptSegmentEntity> e in emissions)
          for (final TranscriptSegmentEntity s in e)
            if (isGapMarker(s) && s.id != union.id) s.id,
      };
      final int first = emissions.indexWhere(
        (List<TranscriptSegmentEntity> e) =>
            e.any((TranscriptSegmentEntity s) => s.text == union.text),
      );
      expect(first, isNonNegative, reason: 'l union est affichée');

      final List<String> bad = <String>[];
      for (int i = first; i < emissions.length; i++) {
        final List<TranscriptSegmentEntity> listed = markersIn(
          emissions[i],
          AudioSource.output,
          111000,
          155000,
        );
        if (listed.length != 1 ||
            listed.any(
              (TranscriptSegmentEntity s) => absorbed.contains(s.id),
            )) {
          bad.add(
            'émission $i : ${listed.map((TranscriptSegmentEntity s) => '${s.id.split('_').last} ${s.text.substring(28)}').join(' + ')}',
          );
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  test(
    'coupure longue en séance (repère provisoire en base, perte déclarée) : à '
    'chaque émission, les repères listés d une source ne se recoupent '
    'jamais, et un repère retiré n y revient pas',
    () {
      fakeAsync((FakeAsync async) {
        final FakeVoxServer server = FakeVoxServer();
        final FakeVoxSocket mic = FakeVoxSocket(server);
        final LiveServiceHarness h = LiveServiceHarness(
          async,
          remote: TranscriptionRemoteDataSourceImpl(
            micClient: mic,
            systemClient: FakeVoxSocket(server),
          ),
        )..start(outputEnabled: false);
        final List<List<TranscriptSegmentEntity>> emissions =
            <List<TranscriptSegmentEntity>>[];
        final StreamSubscription<List<TranscriptSegmentEntity>> sub = h
            .transcription
            .segmentsStream
            .listen(emissions.add);
        addTearDown(sub.cancel);

        int id = 0;
        void speak(int seconds) {
          for (int i = 0; i < seconds * 10; i++, id++) {
            h.audio.emit(
              chunk(AudioSource.input, id, timestampMs: h.t0 + id * 100),
            );
            async.elapse(const Duration(milliseconds: 100));
          }
        }

        speak(10);
        mic
          ..refusing = true
          ..drop();
        speak(150); // le tampon déborde : perte déclarée pendant le provisoire
        mic.refusing = false;
        speak(60); // reconnexion, renvoi

        final List<String> bad = <String>[];
        final Map<String, int> removedAt = <String, int>{};
        Set<String> before = <String>{};
        for (int i = 0; i < emissions.length; i++) {
          final List<TranscriptSegmentEntity> listed =
              <TranscriptSegmentEntity>[
                for (final TranscriptSegmentEntity s in emissions[i])
                  if (s.source == AudioSource.input && isGapMarker(s)) s,
              ];
          for (int a = 0; a < listed.length; a++) {
            for (int b = a + 1; b < listed.length; b++) {
              final ({int startMs, int endMs}) x = markerRange(listed[a].text)!;
              final ({int startMs, int endMs}) y = markerRange(listed[b].text)!;
              if (x.startMs <= y.endMs && y.startMs <= x.endMs) {
                bad.add('émission $i : ${listed[a].text} + ${listed[b].text}');
              }
            }
          }
          final Set<String> now = <String>{
            for (final TranscriptSegmentEntity s in listed) s.id,
          };
          for (final String gone in before.difference(now)) {
            removedAt[gone] = i;
          }
          for (final String back in now.intersection(removedAt.keys.toSet())) {
            // Le repère provisoire peut revenir pour une NOUVELLE coupure,
            // jamais en recoupant un repère listé.
            if (listed.where((TranscriptSegmentEntity s) => s.id != back).any((
              TranscriptSegmentEntity o,
            ) {
              final ({int startMs, int endMs}) x = markerRange(o.text)!;
              final ({int startMs, int endMs}) y = markerRange(
                listed
                    .firstWhere((TranscriptSegmentEntity s) => s.id == back)
                    .text,
              )!;
              return x.startMs <= y.endMs && y.startMs <= x.endMs;
            })) {
              bad.add(
                'émission $i : $back revenu (retiré à ${removedAt[back]})',
              );
            }
          }
          before = now;
        }
        // Le repère provisoire n'est qu'en base (pas à l'écran) ; la perte
        // déclarée, elle, est listée.
        expect(
          emissions.any(
            (List<TranscriptSegmentEntity> e) => e.any(
              (TranscriptSegmentEntity s) =>
                  s.source == AudioSource.input && isGapMarker(s),
            ),
          ),
          isTrue,
          reason: 'la perte a été affichée',
        );
        expect(
          h.segments.of(AudioSource.input).where(isGapMarker),
          hasLength(1),
          reason: 'une perte déclarée, un repère',
        );
        expect(bad.toSet().toList(), isEmpty, reason: bad.toSet().join('\n'));
      });
    },
  );
}
