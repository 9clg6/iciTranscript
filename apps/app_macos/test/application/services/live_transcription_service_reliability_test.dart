import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:core_domain/domain/enum/transcription_health.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

/// Réunions longues (T1) : ce que [LiveTranscriptionService] garantit quand
/// l'app, le serveur ML ou la socket tombent en cours de session.
void main() {
  group('phrase en cours sauvée au fil de l eau (T1.3)', () {
    test('la phrase en cours est déjà en base avant sa fin', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        h.fakeRemote
          ..emitDelta(AudioSource.input, 'Bonjour ')
          ..emitDelta(AudioSource.input, 'à tous');
        async.elapse(const Duration(seconds: 5));

        final List<TranscriptSegmentEntity> saved = h.segments.of(
          AudioSource.input,
        );
        expect(saved, hasLength(1));
        expect(saved.single.text, contains('Bonjour à tous'));
        expect(saved.single.sessionId, h.session.id);
      });
    });

    test('le provisoire suit le texte qui grandit, sans doublon', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        h.fakeRemote.emitDelta(AudioSource.input, 'Bonjour');
        async.elapse(const Duration(seconds: 5));
        h.fakeRemote.emitDelta(AudioSource.input, ' à tous');
        async.elapse(const Duration(seconds: 5));

        final List<TranscriptSegmentEntity> saved = h.segments.of(
          AudioSource.input,
        );
        expect(saved, hasLength(1));
        expect(saved.single.text, contains('Bonjour à tous'));
      });
    });

    test('la phrase finale remplace le provisoire, en base et à l écran', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        h.fakeRemote.emitDelta(AudioSource.input, 'Bonjour à tous');
        async.elapse(const Duration(seconds: 5));

        h.fakeRemote.emitDone(AudioSource.input, 'Bonjour à tous.');
        async.elapse(const Duration(seconds: 1));

        final List<TranscriptSegmentEntity> saved = h.segments.of(
          AudioSource.input,
        );
        expect(saved.map((TranscriptSegmentEntity s) => s.text), <String>[
          'Bonjour à tous.',
        ]);
        final List<TranscriptSegmentEntity> onScreen = h
            .transcription
            .segmentsStream
            .value
            .where((TranscriptSegmentEntity s) => s.source == AudioSource.input)
            .toList();
        expect(onScreen.map((TranscriptSegmentEntity s) => s.text), <String>[
          'Bonjour à tous.',
        ]);
      });
    });

    test('deux phrases successives donnent deux segments', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        for (final String phrase in <String>['On commence.', 'Point budget.']) {
          h.fakeRemote.emitDelta(AudioSource.output, phrase);
          async.elapse(const Duration(seconds: 5));
          h.fakeRemote.emitDone(AudioSource.output, phrase);
          async.elapse(const Duration(seconds: 1));
        }

        expect(
          h.segments.of(AudioSource.output).map((TranscriptSegmentEntity s) {
            return s.text;
          }),
          <String>['On commence.', 'Point budget.'],
        );
      });
    });

    test('une phrase écartée à la fin ne laisse aucun provisoire', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        h.fakeRemote.emitDelta(AudioSource.output, 'Bonjour');
        async.elapse(const Duration(seconds: 5));

        // Texte final en alphabet non latin : écarté comme aujourd'hui.
        h.fakeRemote.emitDone(AudioSource.output, 'Продолжение следует');
        async.elapse(const Duration(seconds: 1));

        expect(h.segments.of(AudioSource.output), isEmpty);
      });
    });
  });

  group('audio enregistré pour chaque session (T1.4)', () {
    test('enregistre micro et son du Mac même sans le coach', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)
          ..start(enablePostProcessing: false);
        final String id = h.session.id;

        for (int i = 0; i < 3; i++) {
          h.audio.emit(chunk(AudioSource.input, i, timestampMs: h.t0 + i));
        }
        for (int i = 0; i < 2; i++) {
          h.audio.emit(chunk(AudioSource.output, i, timestampMs: h.t0 + i));
        }
        async.elapse(const Duration(milliseconds: 500));

        final FakeWavRecorder mic = h.recorders.singleWhere(
          (FakeWavRecorder r) => r.path!.endsWith('${id}_mic.wav'),
        );
        final FakeWavRecorder system = h.recorders.singleWhere(
          (FakeWavRecorder r) => r.path!.endsWith('${id}_system.wav'),
        );
        expect(mic.bytes, 3 * 3200);
        expect(system.bytes, 2 * 3200);

        h.stop();
        expect(mic.closed, isTrue);
        expect(system.closed, isTrue);
      });
    });
  });

  group('crash du serveur en pleine session (T1.2)', () {
    test('relance le serveur, la session reste active et la transcription '
        'reprend', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        expect(h.process.starts, hasLength(1));

        h.process.crash();
        async.elapse(const Duration(seconds: 30));

        expect(h.process.starts, hasLength(2));
        expect(h.process.starts.last.command, LiveServiceHarness.command);
        expect(h.process.starts.last.args, LiveServiceHarness.args);
        expect(
          h.process.starts.last.readyPattern,
          h.process.starts.first.readyPattern,
        );
        expect(h.session.status, SessionStatus.active);
        expect(h.service.isRecording, isTrue);

        h.fakeRemote.emitDone(AudioSource.output, 'On reprend.');
        async.elapse(const Duration(seconds: 1));
        expect(
          h.segments.of(AudioSource.output).map((TranscriptSegmentEntity s) {
            return s.text;
          }),
          contains('On reprend.'),
        );
      });
    });

    test('ne relance pas le serveur après un arrêt demandé', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();
        h.stop();

        h.process.crash();
        async.elapse(const Duration(minutes: 5));

        expect(h.process.starts, hasLength(1));
      });
    });

    test('redevient sain après une relance réussie', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async);
        final List<TranscriptionHealth> health = <TranscriptionHealth>[];
        h.service.transcriptionHealthStream.listen(health.add);
        h.start();

        h.process.crash();
        async.elapse(const Duration(seconds: 30));

        expect(health, contains(TranscriptionHealth.recovering));
        expect(health.last, TranscriptionHealth.healthy);
      });
    });

    test('espace les relances, puis signale l échec sans couper '
        'l enregistrement', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async);
        final List<TranscriptionHealth> health = <TranscriptionHealth>[];
        h.service.transcriptionHealthStream.listen(health.add);
        h.start();

        h.process.failStarts = true;
        h.process.crash();
        async.elapse(const Duration(minutes: 30));

        final List<Duration> restarts = h.process.startTimes.skip(1).toList();
        expect(restarts.length, inInclusiveRange(2, 10));
        final List<Duration> intervals = <Duration>[
          for (int i = 1; i < restarts.length; i++)
            restarts[i] - restarts[i - 1],
        ];
        expect(intervals.last, greaterThan(intervals.first));
        expect(
          restarts.last,
          lessThan(async.elapsed - const Duration(minutes: 10)),
          reason: 'abandon : plus de relance une fois l échec signalé',
        );
        expect(health.last, TranscriptionHealth.failed);

        // L'enregistrement continue : session active, audio reçu et gardé.
        expect(h.session.status, SessionStatus.active);
        expect(h.service.isRecording, isTrue);
        final FakeWavRecorder mic = h.recorders.singleWhere(
          (FakeWavRecorder r) => r.path!.endsWith('_mic.wav'),
        );
        final int before = mic.bytes;
        h.audio.emit(chunk(AudioSource.input, 1, timestampMs: h.t0 + 1800000));
        async.elapse(const Duration(milliseconds: 200));
        expect(mic.bytes, before + 3200);
        expect(h.fakeRemote.sentAudio, isNotEmpty);
      });
    });
  });

  group('repère « transcription interrompue » (T1.2)', () {
    test(
      'une perte d audio laisse un repère horodaté, en base et à l écran',
      () {
        fakeAsync((FakeAsync async) {
          final LiveServiceHarness h = LiveServiceHarness(async)..start();

          h.fakeRemote.emitGap(
            AudioGap(
              source: AudioSource.output,
              startMs: h.t0 + 600000,
              endMs: h.t0 + 690000,
            ),
          );
          async.elapse(const Duration(seconds: 1));

          final TranscriptSegmentEntity marker = h.segments
              .of(AudioSource.output)
              .single;
          expect(marker.timestampMs, 600000);
          expect(marker.text, matches(RegExp(r'00:10:00\s*[–-]\s*00:11:30')));
          expect(h.transcription.segmentsStream.value, contains(marker));
        });
      },
    );

    test('le repère compte les heures au-delà d une heure', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        h.fakeRemote.emitGap(
          AudioGap(
            source: AudioSource.input,
            startMs: h.t0 + 3723000,
            endMs: h.t0 + 3730000,
          ),
        );
        async.elapse(const Duration(seconds: 1));

        expect(
          h.segments.of(AudioSource.input).single.text,
          matches(RegExp(r'01:02:03\s*[–-]\s*01:02:10')),
        );
      });
    });

    test('une coupure rattrapée sans perte ne laisse aucun repère', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        h.process.crash();
        h.fakeRemote.emitConnectionState(domain.ConnectionState.disconnected);
        async.elapse(const Duration(seconds: 30));
        h.fakeRemote.emitConnectionState(domain.ConnectionState.connected);
        async.elapse(const Duration(seconds: 5));

        expect(h.segments.store, isEmpty);
      });
    });
  });

  group('filtre des hallucinations appliqué aux phrases finales (T1.5)', () {
    test('une boucle de répétition est réduite avant d être sauvée', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        h.fakeRemote.emitDone(AudioSource.output, 'okay okay okay okay okay');
        async.elapse(const Duration(seconds: 1));

        expect(
          h.segments.of(AudioSource.output).map((TranscriptSegmentEntity s) {
            return s.text;
          }),
          <String>['okay'],
        );
      });
    });

    test('une formule répétée trois fois de suite n est pas gardée trois '
        'fois, une réponse courte l est', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async)..start();

        for (final String text in <String>[
          'Thank you.',
          'Thank you.',
          'Thank you.',
          'Merci.',
        ]) {
          h.fakeRemote.emitDone(AudioSource.output, text);
          async.elapse(const Duration(seconds: 2));
        }

        final List<String> texts = h.segments
            .of(AudioSource.output)
            .map((TranscriptSegmentEntity s) => s.text)
            .toList();
        expect(
          texts.where((String t) => t == 'Thank you.').length,
          lessThanOrEqualTo(2),
        );
        expect(texts, contains('Merci.'));
      });
    });
  });
}
