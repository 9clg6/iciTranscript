import 'dart:async';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/transcription_health.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';

import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/mistral_fakes.dart';

// Une note avec le moteur en ligne (Mistral), de bout en bout : vrai
// LiveTranscriptionService, vraie source distante, vrais
// MistralRealtimeClient ; seul le serveur Mistral est faux (le test le joue).
//
// Besoins (revue de la PR #33) :
// - mots arrivés tard (un delta après le `done` de la phrase, ou entre
//   `input_audio.end` et `transcription.done`) : dans la note, ou sous un
//   repère de perte ; jamais perdus en silence ;
// - clé refusée en pleine réunion (`error` 401, ou reconnexion en HTTP 401) :
//   l'utilisateur voit « clé refusée » en un temps borné (pas « reprise »
//   sans fin), l'enregistrement WAV continue, le passage perdu est sous un
//   repère.

/// Délai accordé pour voir « clé refusée » : la première reconnexion part
/// 0,5 s après la coupure et le 401 est connu dès elle.
const Duration _keyRejectedWithin = Duration(seconds: 10);

final class _Meeting {
  _Meeting(this.async) {
    h = LiveServiceHarness(async, remote: mistralRemote(server));
    h.service.transcriptionHealthStream.listen(health.add);
    unawaited(
      h.service
          .startTranscription(
            outputEnabled: false,
            serverCommand: LiveServiceHarness.command,
            serverArgs: LiveServiceHarness.args,
            engine: TranscriptionEngine.mistral,
          )
          .catchError((Object _) {}),
    );
    async.elapse(const Duration(seconds: 1));
  }

  final FakeAsync async;
  final FakeMistralServer server = FakeMistralServer();
  final List<TranscriptionHealth> health = <TranscriptionHealth>[];
  late final LiveServiceHarness h;
  int _id = 0;

  /// Position (ms de réunion) du prochain chunk.
  int get atMs => _id * 100;

  /// [count] chunks micro de 100 ms, voisés ou non.
  void say(int count, {bool voiced = true}) {
    for (int i = 0; i < count; i++) {
      final int id = _id++;
      h.audio.emit(
        chunk(
          AudioSource.input,
          id,
          timestampMs: h.t0 + id * 100,
          voiced: voiced,
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
    }
  }

  /// Arrêt, puis assez de temps pour l'attente de fin (bornée à 120 s).
  void stop() {
    unawaited(h.service.stopTranscription());
    async.elapse(const Duration(minutes: 3));
  }

  List<String> texts() => h.segments
      .of(AudioSource.input)
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  /// Repères de perte du micro, en ms de réunion.
  List<({int startMs, int endMs})> markers() => <({int startMs, int endMs})>[
    for (final String t in texts())
      if (t.startsWith(LiveTranscriptionService.gapMarkerPrefix))
        _markerRange(t),
  ];
}

({int startMs, int endMs}) _markerRange(String text) {
  final List<int> ms = RegExp(r'(\d+):(\d{2}):(\d{2})')
      .allMatches(text)
      .map(
        (RegExpMatch m) =>
            ((int.parse(m[1]!) * 60 + int.parse(m[2]!)) * 60 +
                int.parse(m[3]!)) *
            1000,
      )
      .toList();
  return (startMs: ms.first, endMs: ms.last);
}

void main() {
  group('mots arrivés tard', () {
    /// Une phrase (2 s de parole) dont le `done` part après 500 ms de calme,
    /// puis UN delta de plus.
    void sentenceThenLateDelta(_Meeting m) {
      m.say(5);
      m.server.live.delta('Bonjour');
      m.say(15);
      m.server.live.delta(' à tous.');
      m.say(14, voiced: false); // fin d'énoncé (1,2 s), commit final
      m.say(10, voiced: false); // 500 ms de calme : le `done` est parti
      expect(
        m.texts(),
        contains('Bonjour à tous.'),
        reason: 'la phrase a son done avant le delta tardif',
      );
    }

    test('un delta après le done de sa phrase, puis arrêt : ses mots sont '
        'dans la note ou sous un repère', () {
      fakeAsync((FakeAsync async) {
        final _Meeting m = _Meeting(async);
        sentenceThenLateDelta(m);
        m.server.live.delta(' TARDIF');
        m.say(5, voiced: false);

        m.stop();

        final bool inNote = m.texts().any((String t) => t.contains('TARDIF'));
        final bool underMarker = m.markers().any(
          (({int startMs, int endMs}) g) => g.startMs <= 0 && g.endMs >= 2000,
        );
        expect(inNote || underMarker, isTrue, reason: 'note : ${m.texts()}');
      });
    });

    test('un delta entre input_audio.end et transcription.done : ses mots '
        'sont dans la note ou sous un repère', () {
      fakeAsync((FakeAsync async) {
        final _Meeting m = _Meeting(async);
        sentenceThenLateDelta(m);
        // Le serveur finit l'audio reçu après l'arrêt : un dernier delta
        // avant son `transcription.done`. Non observé dans la sonde (dernier
        // delta 2 s avant `input_audio.end`) ; plausible si l'on arrête en
        // pleine parole (deltas ~0,28 s après l'audio).
        m.server.onEnd = (FakeMistralSocket s) =>
            Timer(const Duration(milliseconds: 300), () => s.delta(' TARDIF'));

        m.stop();

        final bool inNote = m.texts().any((String t) => t.contains('TARDIF'));
        final bool underMarker = m.markers().any(
          (({int startMs, int endMs}) g) => g.startMs <= 0 && g.endMs >= 2000,
        );
        expect(inNote || underMarker, isTrue, reason: 'note : ${m.texts()}');
      });
    });
  });

  for (final String how in <String>[
    'error 401 du serveur',
    'socket coupée puis reconnexion en HTTP 401',
  ]) {
    group('clé refusée en pleine réunion ($how)', () {
      /// 5 s de réunion, puis la clé est révoquée ; rend la position du
      /// refus (ms de réunion).
      int revokeKey(_Meeting m) {
        m.say(50);
        m.server.refuseKey = true;
        final int at = m.atMs;
        if (how.startsWith('error')) {
          m.server.live.rejectKey();
        } else {
          m.server.live.close();
        }
        return at;
      }

      test("l'état visible devient « clé refusée » en moins de "
          '${_keyRejectedWithin.inSeconds} s', () {
        fakeAsync((FakeAsync async) {
          final _Meeting m = _Meeting(async);
          expect(m.health.last, TranscriptionHealth.healthy);
          revokeKey(m);

          m.say(_keyRejectedWithin.inMilliseconds ~/ 100);

          expect(
            m.health.last,
            TranscriptionHealth.keyRejected,
            reason: 'états vus : ${m.health}',
          );
        });
      });

      test("l'enregistrement WAV continue après le refus", () {
        fakeAsync((FakeAsync async) {
          final _Meeting m = _Meeting(async);
          revokeKey(m);
          m.say(5);
          final int before = m.h.recorders.first.bytes;

          m.say(300); // 30 s

          expect(m.h.recorders.first.bytes - before, 300 * 3200);
        });
      });

      test("après l'arrêt, le passage depuis le refus est sous un repère", () {
        fakeAsync((FakeAsync async) {
          final _Meeting m = _Meeting(async);
          final int rejectedAt = revokeKey(m);
          m.say(300); // 30 s de parole sans transcription
          final int endMs = m.atMs;

          m.stop();

          expect(
            m.markers().any(
              (({int startMs, int endMs}) g) =>
                  g.startMs <= rejectedAt + 1000 && g.endMs >= endMs - 1000,
            ),
            isTrue,
            reason: 'repères ${m.markers()} ; perdu $rejectedAt–$endMs ms',
          );
        });
      });
    });
  }
}
