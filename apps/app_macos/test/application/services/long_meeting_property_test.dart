import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

/// Besoin T1.6 : une réunion simulée de 90 minutes, horloge factice, sockets
/// factices, une coupure de socket toutes les ~10 minutes et un crash du
/// serveur. Le vrai service et la vraie source distante tournent ensemble.
///
/// Propriétés :
/// - chaque chunk voisé est transcrit une seule fois, ou tombe dans une
///   perte signalée, qui laisse un repère en base (tour 2 : l'audio d'une
///   phrase sans `done` est renvoyé sur la connexion suivante) ;
/// - les horodatages des segments sont monotones par source et suivent le
///   temps de la réunion ;
/// - les tampons reviennent à ~0 après chaque renvoi et restent bornés.
void main() {
  test(
    'une réunion de 90 min avec coupures et crash ne perd rien en silence',
    () {
      fakeAsync((FakeAsync async) {
        final FakeVoxServer server = FakeVoxServer();
        final FakeVoxSocket micSocket = FakeVoxSocket(server);
        final FakeVoxSocket systemSocket = FakeVoxSocket(server);
        final TranscriptionRemoteDataSourceImpl remote =
            TranscriptionRemoteDataSourceImpl(
              micClient: micSocket,
              systemClient: systemSocket,
            );
        final List<AudioGap> gaps = <AudioGap>[];
        remote.audioGaps.listen(gaps.add);

        final LiveServiceHarness h = LiveServiceHarness(async, remote: remote)
          ..start();
        final int t0 = h.t0;

        const int tickMs = 100;
        const int totalTicks = 90 * 60 * 1000 ~/ tickMs;
        int tickAt(int minutes) => minutes * 60 * 1000 ~/ tickMs;

        // Coupures d'une socket (8 s de refus), en alternant les sources.
        final Map<int, FakeVoxSocket> drops = <int, FakeVoxSocket>{
          for (final int m in <int>[10, 20, 30, 40, 60, 70, 80])
            tickAt(m): (m ~/ 10).isOdd ? micSocket : systemSocket,
        };
        final Map<int, FakeVoxSocket> restores = <int, FakeVoxSocket>{
          for (final MapEntry<int, FakeVoxSocket> d in drops.entries)
            d.key + 80: d.value,
        };
        // Crash du serveur à 50 min ; la relance recharge le modèle 200 s,
        // plus que la borne de 120 s : une perte est attendue.
        final int crashTick = tickAt(50);
        // Contrôle des tampons 60 s après la fin de chaque coupure.
        final Set<int> drainedChecks = <int>{
          for (final int r in restores.keys) r + 600,
          crashTick + 2000 + 600,
        };

        bool micVoiced(int ms) => ms % 10000 < 7000;
        bool systemVoiced(int ms) => (ms + 5000) % 10000 < 7000;
        final Map<AudioSource, List<int>> voicedIds = <AudioSource, List<int>>{
          AudioSource.input: <int>[],
          AudioSource.output: <int>[],
        };
        Duration maxBuffered = Duration.zero;
        final List<String> notDrained = <String>[];

        for (int i = 0; i < totalTicks; i++) {
          final int ms = i * tickMs;
          if (drops[i] case final FakeVoxSocket socket) {
            socket
              ..refusing = true
              ..drop();
          }
          if (restores[i] case final FakeVoxSocket socket) {
            socket.refusing = false;
          }
          if (i == crashTick) {
            server.up = false;
            micSocket.drop();
            systemSocket.drop();
            h.process
              ..startDuration = const Duration(seconds: 200)
              ..onReady = () {
                server.up = true;
              }
              ..crash();
          }

          final bool mv = micVoiced(ms);
          final bool sv = systemVoiced(ms);
          if (mv) voicedIds[AudioSource.input]!.add(i);
          if (sv) voicedIds[AudioSource.output]!.add(i);
          h.audio
            ..emit(
              chunk(AudioSource.input, i, timestampMs: t0 + ms, voiced: mv),
            )
            ..emit(
              chunk(AudioSource.output, i, timestampMs: t0 + ms, voiced: sv),
            );
          async.elapse(const Duration(milliseconds: tickMs));

          if (i % 10 == 0) {
            for (final AudioSource source in AudioSource.values) {
              final Duration buffered = remote.bufferedAudio(source);
              if (buffered > maxBuffered) maxBuffered = buffered;
            }
          }
          if (drainedChecks.contains(i)) {
            for (final AudioSource source in AudioSource.values) {
              final Duration buffered = remote.bufferedAudio(source);
              if (buffered > const Duration(milliseconds: 200)) {
                notDrained.add('${source.name} à ${ms ~/ 1000} s : $buffered');
              }
            }
          }
        }
        async.elapse(const Duration(seconds: 5));

        expect(h.session.status, SessionStatus.active);
        expect(h.service.isRecording, isTrue);

        // 1. Chaque chunk voisé est transcrit une fois, ou compté dans une
        // perte signalée ; jamais les deux. Sur une même connexion, aucun
        // chunk n'est envoyé deux fois ni dans le désordre (le renvoi d'une
        // phrase sans `done` se fait sur la connexion suivante).
        final Map<AudioSource, FakeVoxSocket> sockets =
            <AudioSource, FakeVoxSocket>{
              AudioSource.input: micSocket,
              AudioSource.output: systemSocket,
            };
        for (final AudioSource source in AudioSource.values) {
          final FakeVoxSocket socket = sockets[source]!;
          for (final List<int> ids in socket.connections) {
            for (int k = 1; k < ids.length; k++) {
              if (ids[k] <= ids[k - 1]) {
                fail(
                  '${source.name} : chunk ${ids[k]} reçu après ${ids[k - 1]} '
                  'sur la même connexion (doublon ou désordre)',
                );
              }
            }
          }
          expect(
            socket.transcribedTwice,
            isEmpty,
            reason: '${source.name} : chunks transcrits deux fois',
          );
          bool inGap(int id) => gaps.any(
            (AudioGap g) =>
                g.source == source &&
                t0 + id * tickMs >= g.startMs &&
                t0 + id * tickMs < g.endMs,
          );
          // La dernière phrase, encore en cours à la fin, est exclue.
          final List<int> lost = voicedIds[source]!
              .where(
                (int id) =>
                    id < totalTicks - 100 &&
                    !socket.transcribedIds.contains(id) &&
                    !inGap(id),
              )
              .toList();
          expect(
            lost,
            isEmpty,
            reason:
                '${source.name} : ${lost.length} chunks voisés jamais '
                'transcrits ni signalés (premier : '
                '${lost.isEmpty ? '-' : lost.first})',
          );
          expect(
            socket.transcribedIds.where(inGap),
            isEmpty,
            reason: 'une perte signalée ne couvre aucun chunk transcrit',
          );
        }

        // 2. Chaque perte laisse un repère en base, à son heure.
        final Set<(AudioSource, int)> markers = <(AudioSource, int)>{
          for (final AudioGap g in gaps) (g.source, g.startMs - t0),
        };
        for (final (AudioSource source, int offset) in markers) {
          expect(
            h.segments.store.values.any(
              (TranscriptSegmentEntity s) =>
                  s.source == source && s.timestampMs == offset,
            ),
            isTrue,
            reason: 'repère manquant pour la perte ${source.name} à $offset ms',
          );
        }

        // 3. Horodatages monotones par source, sur le temps de la réunion.
        for (final AudioSource source in AudioSource.values) {
          final List<int> stamps = h.segments
              .of(source)
              .where(
                (TranscriptSegmentEntity s) =>
                    !markers.contains((source, s.timestampMs)),
              )
              .map((TranscriptSegmentEntity s) => s.timestampMs)
              .toList();
          final FakeVoxSocket socket = source == AudioSource.input
              ? micSocket
              : systemSocket;
          expect(socket.doneSent, greaterThan(400), reason: source.name);
          expect(
            stamps.length,
            socket.doneSent,
            reason:
                '${source.name} : chaque phrase finale du serveur est '
                'sauvée une fois, aucune n en écrase une autre',
          );
          for (int k = 1; k < stamps.length; k++) {
            expect(
              stamps[k],
              greaterThanOrEqualTo(stamps[k - 1]),
              reason: '${source.name} : segment $k remonte le temps',
            );
          }
          expect(
            stamps.last,
            greaterThan(80 * 60 * 1000),
            reason: 'les horodatages suivent l horloge de la réunion',
          );
        }

        // 4. Tampons bornés et vidés après chaque renvoi.
        expect(notDrained, isEmpty);
        expect(maxBuffered, lessThanOrEqualTo(const Duration(minutes: 5)));
        for (final AudioSource source in AudioSource.values) {
          expect(
            remote.bufferedAudio(source),
            lessThanOrEqualTo(const Duration(milliseconds: 200)),
          );
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
