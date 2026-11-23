import 'dart:async';

import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../helpers/data_source_bench.dart';
import '../helpers/fake_websocket_client.dart';

/// Tour 10, point 1 — PERTE SILENCIEUSE (sonde 8, scénario Dlag, son
/// système). La phrase 11 (audio 102–110 s) est arrivée en direct, mais son
/// `done` a reçu la fenêtre de la phrase 12 (111,6 s) pendant le rattrapage
/// en retard ; le rattrapage de la perte 1:49–1:58 l'a ensuite remplacée
/// par le temps et n'a retranscrit que 108–120 s : la phrase 11 a disparu,
/// sans repère.
///
/// Rejeu du calendrier enregistré (proxy de la sonde) : retard des réponses
/// 40 s de 20 à 61 s ; refus de 60 à 210 s ; réponses immédiates ensuite ;
/// retard 30 s à partir de 230 s. Parole continue de phrases de 7,5 s
/// séparées de 2,5 s, comme le texte de référence.
///
/// Condition qui les a mal appariés (même connexion) : pendant le
/// rattrapage étalé d'un serveur plus lent que le temps réel, le tampon
/// dépasse 120 s alors que la phrase k est en partie en vol (la borne de
/// 30 s a arrêté l'envoi au milieu de son audio) ; l'éviction jette la fin
/// non envoyée de k ET son commit final (« commit resté en tête »), donc sa
/// fenêtre ; le commit de k+1 part ensuite, et le `done` du serveur, qui
/// transcrit l'audio reçu de k, prend la fenêtre de k+1. La fin jetée de k
/// n'est signalée qu'à la coupure suivante (sonde 8 : fermeture à 295 s,
/// perte 1:49–1:58 = fin de 11 + 12).
///
/// Preuve (svc_Dlag.jsonl) : une seule connexion de 215,7 s à 295,0 s ; les
/// `done` de 8, 9, 10 ont pris 74,3 / 83,7 / 92,8 s ; celui de 11 (texte
/// entier) a pris 111,6 s : la fenêtre de 11 n'est jamais entrée dans la
/// file d'attente — seule voie : le commit final de 11 jeté non envoyé.
///
/// Attendu : un `done` ne reçoit JAMAIS la fenêtre d'une phrase plus
/// récente que celle qu'il transcrit (la fenêtre commence au plus tard au
/// premier chunk de son audio, à 1,5 s près) ; aucun chunk voisé n'est
/// perdu sans être signalé. Les données (phrase 11 rendue entière par le
/// serveur) appellent la fenêtre de k elle-même.
void main() {
  test('sous le calendrier de la sonde 8, chaque done garde la fenêtre de sa '
      'propre phrase', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = _replayProbe8(async);

      // Un seul abonné au flux (le banc) : le décodage est fait par abonné.
      final List<TranscriptEventRemoteModel> done = b.systemEvents
          .where(
            (TranscriptEventRemoteModel e) =>
                e.type == 'response.audio_transcript.done',
          )
          .toList();
      expect(done.length, b.system.doneUtterances.length);
      final List<String> wrong = <String>[];
      for (int i = 0; i < done.length; i++) {
        final UtteranceWindow? w = b.dataSource.windowOf(done[i]);
        final List<int> ids = b.system.doneUtterances[i];
        if (w == null || ids.isEmpty) continue;
        final int audioStart = DataSourceBench.t0 + ids.first * 100;
        if (w.startMs > audioStart + 1500) {
          wrong.add(
            'done $i : audio dès ${(audioStart - DataSourceBench.t0) / 1000} '
            's, fenêtre à ${(w.startMs - DataSourceBench.t0) / 1000} s',
          );
        }
      }
      expect(wrong, isEmpty, reason: wrong.join('\n'));
    });
  });

  test('sous le même calendrier, à l\'arrêt, chaque chunk voisé est transcrit '
      'ou couvert par une perte signalée', () {
    fakeAsync((FakeAsync async) {
      final DataSourceBench b = _replayProbe8(async);
      unawaited(b.dataSource.disconnect());
      async.flushMicrotasks();

      final List<int> silent = <int>[
        for (int id = 0; id < 2900; id++)
          if (id % 100 < 75 &&
              !b.system.transcribedIds.contains(id) &&
              !b.inGap(AudioSource.output, id))
            id,
      ];
      expect(
        silent,
        isEmpty,
        reason:
            '${silent.length} chunks ni transcrits ni signalés '
            '(premier : ${silent.isEmpty ? '-' : silent.first})',
      );
    });
  });
}

DataSourceBench _replayProbe8(FakeAsync async) {
  final DataSourceBench b = DataSourceBench(async);
  // Serveur séquentiel, plus lent que le temps réel pendant le
  // rattrapage (machine chargée) : le tampon déborde pendant que la
  // phrase en tête est en vol.
  final _SlowServer server = _SlowServer(async)..attach(b.system);
  for (int id = 0; id < 3000; id++) {
    if (id == 200) server.lag = const Duration(seconds: 40);
    if (id == 600) {
      b.system
        ..accepting = false
        ..drop();
    }
    if (id == 610) server.lag = Duration.zero;
    if (id == 2100) b.system.accepting = true;
    if (id == 2300) server.lag = const Duration(seconds: 30);
    b.tick(id, voiced: <AudioSource, bool>{AudioSource.output: id % 100 < 75});
  }
  async.elapse(const Duration(minutes: 2));
  return b;
}

/// File unique, [speed] fois le temps réel, plus un retard [lag] des
/// réponses (proxy de la sonde).
final class _SlowServer {
  _SlowServer(this.async);

  final FakeAsync async;
  double speed = 0.8;
  Duration lag = Duration.zero;
  Duration _busyUntil = Duration.zero;

  void attach(FakeWebSocketClient socket) {
    socket.onFinalCommit = (List<int> ids, int generation) {
      final Duration now = async.elapsed;
      final Duration start = _busyUntil > now ? _busyUntil : now;
      _busyUntil =
          start + Duration(milliseconds: (ids.length * 100 / speed).round());
      Timer(_busyUntil + lag - now, () {
        socket.emitIfAlive(generation, <String, Object>{
          'type': 'response.audio_transcript.done',
          'text': 'phrase',
        });
      });
    };
  }
}
