import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

/// Tour 5, point 3 : aucune voie silencieuse à l'arrêt. L'audio encore en
/// tampon ou en vol est soit livré (l'arrêt attend le rattrapage, 120 s au
/// plus, en publiant ce qui reste pour l'écran « finalisation… »), soit
/// signalé par une seule perte par source, écrite en repère. L'utilisateur
/// peut passer l'attente.
///
/// API supposée sur LiveTranscriptionService :
/// - `Stream<Duration> finalisingRemainingStream` : audio restant à
///   transcrire pendant l'attente de l'arrêt, `Duration.zero` à la fin ;
/// - `void skipFinalising()` : arrête d'attendre ; le reste devient perte.
void main() {
  late FakeAsync clock;
  late FakeVoxServer server;
  late FakeVoxSocket mic;
  late TranscriptionRemoteDataSourceImpl remote;
  late LiveServiceHarness h;
  late List<AudioGap> gaps;
  late List<int> voiced;

  void setUpIn(FakeAsync async, {double? speed = 2}) {
    clock = async;
    server = FakeVoxServer(now: () => async.elapsed, speed: speed);
    mic = FakeVoxSocket(server);
    remote = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: FakeVoxSocket(server),
    );
    gaps = <AudioGap>[];
    remote.audioGaps.listen(gaps.add);
    voiced = <int>[];
    h = LiveServiceHarness(async, remote: remote)..start(outputEnabled: false);
  }

  /// Parole micro : 8 s de voix, 2 s de pause par cycle de 10 s.
  void speak(int fromId, int count) {
    for (int id = fromId; id < fromId + count; id++) {
      final bool v = id % 100 < 80;
      if (v) voiced.add(id);
      h.audio.emit(
        chunk(AudioSource.input, id, timestampMs: h.t0 + id * 100, voiced: v),
      );
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  /// 60 s de coupure en parlant, retour du serveur, puis 3 s de parole :
  /// un arriéré d'environ 50 s attend son rattrapage étalé.
  void backlog() {
    speak(0, 50);
    mic
      ..refusing = true
      ..drop();
    speak(50, 600);
    mic.refusing = false;
    speak(650, 30);
  }

  ({bool stopped, Duration took}) stop({Duration? skipAfter}) {
    bool stopped = false;
    final Duration askedAt = clock.elapsed;
    unawaited(h.service.stopTranscription().then((_) => stopped = true));
    bool skipped = false;
    while (!stopped && clock.elapsed - askedAt < const Duration(seconds: 200)) {
      if (!skipped &&
          skipAfter != null &&
          clock.elapsed - askedAt >= skipAfter) {
        skipped = true;
        h.service.skipFinalising();
      }
      clock.elapse(const Duration(milliseconds: 100));
    }
    return (stopped: stopped, took: clock.elapsed - askedAt);
  }

  bool inGap(int id) => gaps.any(
    (AudioGap g) =>
        g.source == AudioSource.input &&
        h.t0 + id * 100 >= g.startMs &&
        h.t0 + id * 100 < g.endMs,
  );

  List<TranscriptSegmentEntity> markers() => h.segments
      .of(AudioSource.input)
      .where(
        (TranscriptSegmentEntity s) =>
            s.text.startsWith('Transcription interrompue'),
      )
      .toList();

  void expectNoSilentLoss() {
    final List<int> neither = voiced
        .where((int id) => !mic.transcribedIds.contains(id) && !inGap(id))
        .toList();
    expect(
      neither,
      isEmpty,
      reason:
          '${neither.length} chunks ni transcrits ni signalés '
          '(premier : ${neither.isEmpty ? '-' : neither.first})',
    );
    for (final AudioGap g in gaps) {
      expect(
        markers().any(
          (TranscriptSegmentEntity s) => s.timestampMs == g.startMs - h.t0,
        ),
        isTrue,
        reason: 'chaque perte a son repère',
      );
    }
  }

  test('arrêt pendant un rattrapage étalé : l arrêt attend, publie ce qui '
      'reste, et tout est transcrit', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      final List<Duration> remaining = <Duration>[];
      h.service.finalisingRemainingStream.listen(remaining.add);
      backlog();

      final ({bool stopped, Duration took}) r = stop();

      expect(r.stopped, isTrue);
      expect(r.took, lessThanOrEqualTo(const Duration(seconds: 120)));
      expect(remaining, isNotEmpty);
      expect(remaining.first, greaterThan(Duration.zero));
      expect(remaining.last, Duration.zero);
      for (int k = 1; k < remaining.length; k++) {
        expect(remaining[k], lessThanOrEqualTo(remaining[k - 1]));
      }
      expect(gaps, isEmpty);
      expect(markers(), isEmpty);
      expectNoSilentLoss();
      expect(h.session.status, SessionStatus.completed);
    });
  });

  test('l utilisateur passe l attente : arrêt immédiat, un repère couvre '
      'ce qui restait', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      backlog();

      final ({bool stopped, Duration took}) r = stop(
        skipAfter: const Duration(seconds: 2),
      );

      expect(r.stopped, isTrue);
      expect(r.took, lessThanOrEqualTo(const Duration(seconds: 3)));
      expect(markers(), hasLength(1));
      expectNoSilentLoss();
      expect(h.session.status, SessionStatus.completed);
    });
  });

  test('arrêt après une fermeture de socket passée inaperçue : rien ne se '
      'perd en silence', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async, speed: null);
      speak(0, 245); // fin en pleine phrase
      mic.drop(); // fermeture non notifiée, plus aucun envoi micro

      final ({bool stopped, Duration took}) r = stop();

      expect(r.stopped, isTrue);
      expect(r.took, lessThanOrEqualTo(const Duration(seconds: 125)));
      expect(markers().length, lessThanOrEqualTo(1));
      expectNoSilentLoss();
    });
  });

  test('arrêt pendant une coupure qui dure : arrêt borné, une perte et '
      'son repère', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async, speed: null);
      speak(0, 100);
      mic
        ..refusing = true
        ..drop();
      speak(100, 200);

      final ({bool stopped, Duration took}) r = stop();

      expect(r.stopped, isTrue);
      expect(r.took, lessThanOrEqualTo(const Duration(seconds: 125)));
      expect(markers(), hasLength(1));
      expectNoSilentLoss();
      expect(h.session.status, SessionStatus.completed);
    });
  });
}
