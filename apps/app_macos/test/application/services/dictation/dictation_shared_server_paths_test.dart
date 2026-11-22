import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/settings_fakes.dart';

/// Dictée (T2), revue du 22/11 : chemins entre la dictée, une réunion et le
/// serveur partagé.
///
/// Comportements figés ici (corrigés sans spec, commit cd6a292) :
/// - un appui pendant qu'une réunion démarre est ignoré (une seule capture) ;
/// - serveur demandé deux fois (dictée activée, puis réunion) : un seul
///   démarrage (un second tue le premier) ;
/// - le dernier `done` d'une dictée en réunion, arrivé juste après le
///   relâchement, n'est pas perdu ; s'il ne vient jamais, la dictée finit
///   quand même (bornée) et le micro peut servir à une autre dictée ;
/// - `lendServer` demandé pendant une dictée hors réunion attend sa fin
///   (bornée), puis arrête le serveur.
///
/// Corrections demandées :
/// - la dictée prend le micro choisi dans Réglages (`selected_mic_id` de
///   prefs.json, lu à chaque appui), pas celui du système ;
/// - une dictée encore en « démarrage » quand un enregistrement commence
///   n'est pas perdue. Choix : la réunion attend (comme pour une dictée qui
///   écoute) que le serveur — qu'elle aurait attendu de toute façon — soit
///   prêt ; la dictée transcrit son audio gardé sur son propre flux, produit
///   son texte, ferme son flux, puis la réunion ouvre sa capture et ses
///   flux. Serveur jamais prêt : erreur explicite, jamais une perte muette.
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );

  setUp(resetPrefs);

  void startRecording(DictationHarness d) => unawaited(
    d.live.service.startTranscription(
      outputEnabled: true,
      serverCommand: LiveServiceHarness.command,
      serverArgs: LiveServiceHarness.args,
    ),
  );

  group('chemins figés', () {
    test('appui pendant le démarrage d une réunion : ignoré, la réunion a sa '
        'capture', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(seconds: 3);
        d.launch(clipboardMode);
        startRecording(d);
        async.elapse(const Duration(milliseconds: 100));

        d.press();
        d.say(5);
        d.release();
        async.elapse(const Duration(seconds: 5));

        expect(d.state, isA<DictationIdle>());
        expect(
          d.audio.log.where((String e) => e.startsWith('capture.start')),
          <String>['capture.start(output: true)'],
        );
        expect(d.live.service.isRecording, isTrue);
        expect(d.output.log, isEmpty);
      });
    });

    test('serveur demandé par la dictée puis par la réunion : un seul '
        'démarrage', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(seconds: 3);
        d.launch(clipboardMode);
        async.elapse(const Duration(seconds: 1));

        startRecording(d);
        async.elapse(const Duration(seconds: 5));

        expect(d.process.starts, hasLength(1));
        expect(d.live.service.isRecording, isTrue);
      });
    });

    test('emprunt du serveur pendant une dictée hors réunion : attend sa fin, '
        'puis arrête le serveur', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async)
          ..launch(clipboardMode);
        final List<ServerState> states = <ServerState>[];
        d.process.stateStream.listen(states.add);
        bool worked = false;
        d.press();
        d.say(10);

        unawaited(d.controller.lendServer(() async => worked = true));
        async.elapse(const Duration(seconds: 2));
        expect(worked, isFalse);
        expect(states, isNot(contains(ServerState.stopped)));

        d.release();
        d.remote.emitDone('Avant le coach.');
        async.elapse(const Duration(seconds: 1));

        expect(d.output.copies, <String>['Avant le coach.']);
        expect(worked, isTrue);
        expect(states, contains(ServerState.stopped));
      });
    });

    test('emprunt pendant une dictée qui ne finit pas : attente bornée', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async)
          ..launch(clipboardMode);
        bool worked = false;
        d.press();

        unawaited(d.controller.lendServer(() async => worked = true));
        async.elapse(
          DictationController.serverStartTimeout +
              DictationController.finalTextTimeout +
              const Duration(seconds: 1),
        );

        expect(worked, isTrue);
      });
    });
  });

  group('dernier done d une dictée en réunion', () {
    late FakeVoxSocket mic;
    late LiveServiceHarness h;
    late DictationHarness d;
    int id = 0;

    void setUpIn(FakeAsync async) {
      id = 0;
      final FakeVoxServer server = FakeVoxServer();
      mic = FakeVoxSocket(server)..autoReply = false;
      h = LiveServiceHarness(
        async,
        remote: TranscriptionRemoteDataSourceImpl(
          micClient: mic,
          systemClient: FakeVoxSocket(server),
        ),
      );
      d = DictationHarness(async, live: h)..launch(clipboardMode);
      h.start(outputEnabled: false);
    }

    void run(FakeAsync async, int count, {bool voiced = true}) {
      for (int i = 0; i < count; i++) {
        h.audio.emit(
          chunk(
            AudioSource.input,
            id,
            timestampMs: h.t0 + id * 100,
            voiced: voiced,
          ),
        );
        id++;
        async.elapse(const Duration(milliseconds: 100));
      }
    }

    void done(String text) => mic.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': text,
    });

    List<String> note() => h.segments
        .of(AudioSource.input)
        .map((TranscriptSegmentEntity s) => s.text)
        .toList();

    test(
      'done arrivé juste après le relâchement : produit, hors de la note',
      () {
        fakeAsync((FakeAsync async) {
          setUpIn(async);
          run(async, 10, voiced: false);
          d.press();
          run(async, 20);
          run(async, 14, voiced: false); // pause : la phrase dictée est close
          d.release();
          async.elapse(const Duration(milliseconds: 20));
          done('Dicté juste avant.');
          async.elapse(const Duration(seconds: 1));

          expect(d.state, isA<DictationDone>(), reason: '${d.state} ; note : ${note()}');
        expect(d.output.copies, <String>['Dicté juste avant.']);
          expect(note(), isNot(contains('Dicté juste avant.')));
        });
      },
    );

    test('done jamais arrivé : la dictée finit (bornée) et une nouvelle '
        'dictée est possible dans la même réunion', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        run(async, 10, voiced: false);
        d.press();
        run(async, 20);
        d.release(); // commit de la phrase dictée : son done ne viendra pas
        async.elapse(const Duration(seconds: 90));
        expect(d.state, isNot(isA<DictationTranscribing>()));

        d.press();

        expect(d.state, isA<DictationListening>());
      });
    });
  });

  group('corrections demandées', () {
    test(
      'la dictée prend le micro choisi dans Réglages, relu à chaque appui',
      () {
        fakeAsync((FakeAsync async) {
          final DictationHarness d = DictationHarness(async)
            ..launch(clipboardMode);
          unawaited(
            PrefsStore().update(<String, Object?>{'selected_mic_id': 'mic-2'}),
          );
          async.elapse(Duration.zero);

          d.holdAndSay(5);
          d.remote.emitDone('Un.');
          async.elapse(Duration.zero);
          unawaited(
            PrefsStore().update(<String, Object?>{'selected_mic_id': 'mic-3'}),
          );
          async.elapse(Duration.zero);
          d.holdAndSay(5);

          expect(d.audio.inputDeviceIds, <String?>['mic-2', 'mic-3']);
        });
      },
    );

    test('aucun micro choisi : celui du système', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async)
          ..launch(clipboardMode);

        d.press();

        expect(d.audio.inputDeviceIds, <String?>[null]);
      });
    });

    test('dictée en « démarrage » quand un enregistrement commence : son '
        'audio est transcrit et produit, puis la réunion démarre', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(seconds: 8);
        d.launch(clipboardMode);
        d.press();
        expect(d.state, isA<DictationStarting>());
        d.say(20);

        startRecording(d);
        async.elapse(const Duration(seconds: 8));
        expect(d.state, isNot(isA<DictationError>()));
        expect(d.remote.connects, hasLength(1));
        expect(d.remote.sentAudio, hasLength(20));
        d.remote.emitDone('Juste avant la réunion.');
        async.elapse(const Duration(seconds: 2));

        expect(d.output.copies, <String>['Juste avant la réunion.']);
        final List<String> log = d.audio.log;
        final int meeting = log.indexOf('capture.start(output: true)');
        expect(meeting, greaterThan(0));
        expect(
          log.sublist(0, meeting),
          containsAll(<String>['capture.stop', 'dictation.disconnect']),
        );
        expect(d.live.service.isRecording, isTrue);
        expect(d.process.starts, hasLength(1));
      });
    });

    test('dictée en « démarrage », serveur jamais prêt, un enregistrement '
        'commence : fin explicite, pas une perte muette', () {
      fakeAsync((FakeAsync async) {
        final DictationHarness d = DictationHarness(async);
        d.process.startDuration = const Duration(minutes: 10);
        d.launch(clipboardMode);
        d.press();
        d.say(10);

        startRecording(d);
        async.elapse(
          DictationController.serverStartTimeout +
              DictationController.finalTextTimeout +
              const Duration(seconds: 5),
        );

        expect(d.state, isA<DictationError>());
      });
    });
  });
}
