import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Dictée (T2) pendant un enregistrement : AUCUN flux en plus (un 3e flux
/// fait exploser les délais du serveur, mesuré). La dictée prend le texte
/// du micro que la réunion transcrit déjà entre l'appui et le relâchement ;
/// ce texte n'est pas sauvé comme segment de la note (choix : non sauvé,
/// plutôt que sauvé masqué : pas de changement de schéma). La réunion n'est
/// jamais mise en pause ; l'audio système n'est pas touché ; après la dictée
/// le micro revient à la note.
///
/// Choix tranchés ici :
/// - phrase à cheval sur l'appui : ce qui est dit avant l'appui reste à la
///   note, ce qui est dit après va à la dictée ;
/// - attribution par phrase (fenêtre de parole), pas par heure d'arrivée :
///   une phrase de réunion finie avant l'appui mais transcrite après reste
///   à la note ;
/// - dictée annulée pendant la réunion : ses mots sont jetés, ils ne
///   reviennent pas dans la note ;
/// - démarrer un enregistrement pendant une dictée la termine d'abord
///   (texte produit), puis la réunion démarre : jamais deux captures.
///
/// Vrai service de réunion et vraie source distante, sockets factices
/// (`FakeVoxSocket` répond à chaque commit final 400 ms plus tard).
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );

  late FakeAsync clock;
  late FakeVoxSocket mic;
  late FakeVoxSocket system;
  late LiveServiceHarness h;
  late DictationHarness d;
  int id = 0;

  void setUpIn(FakeAsync async) {
    clock = async;
    id = 0;
    final FakeVoxServer server = FakeVoxServer();
    mic = FakeVoxSocket(server);
    system = FakeVoxSocket(server)..reply = (int n) => 'Système $n.';
    h = LiveServiceHarness(
      async,
      remote: TranscriptionRemoteDataSourceImpl(
        micClient: mic,
        systemClient: system,
      ),
    );
    d = DictationHarness(async, live: h)..launch(clipboardMode);
    h.start();
  }

  /// [count] × 100 ms d'audio des deux sources, voisé ou non par source.
  void run(int count, {bool mic = false, bool system = false}) {
    for (int i = 0; i < count; i++) {
      final int ts = h.t0 + id * 100;
      h.audio
        ..emit(chunk(AudioSource.input, id, timestampMs: ts, voiced: mic))
        ..emit(chunk(AudioSource.output, id, timestampMs: ts, voiced: system));
      id++;
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  List<String> note(AudioSource source) =>
      h.segments.of(source).map((TranscriptSegmentEntity s) => s.text).toList();

  List<String> onScreen() => h.service.segmentsStream.value
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  /// Réponses du micro dans l'ordre ; une phrase en trop se voit.
  String Function(int) replies(List<String> texts) =>
      (int n) => n <= texts.length ? texts[n - 1] : 'Phrase en trop $n.';

  void micSays(String type, String key, String text) =>
      mic.emit(<String, Object>{'type': type, key: text});

  test('la parole dite pendant la dictée va à la sortie, jamais à la note ; '
      'avant et après, le micro va à la note', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.reply = replies(<String>[
        'Réunion avant.',
        'Texte dicté.',
        'Réunion après.',
      ]);

      run(20, mic: true);
      d.press();
      run(5, mic: true);
      micSays('response.audio_transcript.delta', 'delta', 'Texte dicté en');
      run(25, mic: true); // plus de 2 s : la sauvegarde au fil de l'eau passe
      final List<String> midway = <String>[
        ...note(AudioSource.input),
        ...onScreen(),
      ];
      expect(midway, isNot(anyElement(contains('dicté'))));
      d.release();
      run(20, mic: true);
      run(20); // silence : la phrase de réunion suivante se termine
      async.elapse(const Duration(seconds: 2));

      expect(d.output.copies, <String>['Texte dicté.']);
      expect(note(AudioSource.input), <String>[
        'Réunion avant.',
        'Réunion après.',
      ]);
      expect(onScreen(), isNot(anyElement(contains('dicté'))));
      expect(d.state, isA<DictationDone>());
    });
  });

  test('une phrase de réunion finie avant l appui mais transcrite après reste '
      'dans la note', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.autoReply = false;

      run(20, mic: true);
      run(15); // silence : commit final de la phrase de réunion
      d.press();
      run(5, mic: true);
      micSays('response.audio_transcript.done', 'text', 'Réunion avant.');
      run(20, mic: true);
      d.release();
      run(3);
      micSays('response.audio_transcript.done', 'text', 'Texte dicté.');
      async.elapse(const Duration(seconds: 1));

      expect(note(AudioSource.input), <String>['Réunion avant.']);
      expect(d.output.copies, <String>['Texte dicté.']);
    });
  });

  test('l audio système n est pas touché : une phrase dite à travers la '
      'dictée reste une seule ligne', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.reply = replies(<String>[
        'Réunion avant.',
        'Texte dicté.',
        'Réunion après.',
      ]);

      run(10, system: true);
      run(5, mic: true, system: true);
      d.press();
      run(30, mic: true, system: true);
      d.release();
      run(5, mic: true, system: true);
      run(10, system: true);
      run(20); // silence des deux côtés
      async.elapse(const Duration(seconds: 2));

      expect(note(AudioSource.output), <String>['Système 1.']);
      expect(system.doneSent, 1);
      expect(d.output.copies, <String>['Texte dicté.']);
    });
  });

  test('l enregistrement continue : ni pause ni arrêt, le WAV micro reçoit '
      'tout, aucune capture ni aucun flux en plus', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      run(10, mic: true);
      final FakeWavRecorder micWav = h.recorders.first;
      final int before = micWav.chunks;

      d.press();
      run(30, mic: true);
      expect(micWav.chunks, greaterThanOrEqualTo(before + 30));
      d.release();
      run(20);
      async.elapse(const Duration(seconds: 2));

      expect(h.audio.startCalls, 1);
      expect(h.audio.stopCalls, 0);
      expect(h.service.isRecording, isTrue);
      expect(h.session.status, SessionStatus.active);
      expect(d.remote.connects, isEmpty, reason: 'pas de 3e flux');
      expect(d.remote.sentAudio, isEmpty);
      expect(mic.connectCalls, 1);
      expect(d.output.copies, hasLength(1));
    });
  });

  test('dictée annulée pendant la réunion : ses mots ne vont ni à la sortie '
      'ni à la note, la note reprend ensuite', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.reply = replies(<String>[
        'Réunion avant.',
        'Texte annulé.',
        'Réunion après.',
      ]);

      run(20, mic: true);
      d.press();
      run(30, mic: true);
      d.cancel();
      run(20, mic: true);
      run(20);
      async.elapse(const Duration(seconds: 2));

      expect(d.output.log, isEmpty);
      expect(d.state, isA<DictationIdle>());
      expect(note(AudioSource.input), <String>[
        'Réunion avant.',
        'Réunion après.',
      ]);
      expect(onScreen(), isNot(anyElement(contains('annulé'))));
    });
  });

  test('texte de la dictée arrivé après le délai de garde : toujours hors de '
      'la note (presse-papiers), la note reprend ensuite', () {
    fakeAsync((FakeAsync async) {
      setUpIn(async);
      mic.autoReply = false;
      run(10);
      d.press();
      run(30, mic: true);
      d.release();
      run(5);
      async.elapse(DictationController.finalTextTimeout);
      expect(d.state, isA<DictationError>());

      micSays('response.audio_transcript.done', 'text', 'Texte dicté.');
      async.elapse(const Duration(seconds: 1));
      run(20, mic: true);
      run(20);
      micSays('response.audio_transcript.done', 'text', 'Réunion après.');
      async.elapse(const Duration(seconds: 1));

      expect(note(AudioSource.input), <String>['Réunion après.']);
      expect(onScreen(), isNot(anyElement(contains('dicté'))));
      expect(d.output.copies, <String>['Texte dicté.']);
    });
  });

  test('démarrer un enregistrement pendant une dictée la termine d abord '
      '(texte produit), puis la réunion démarre sa capture', () {
    fakeAsync((FakeAsync async) {
      final DictationHarness d = DictationHarness(async)..launch(clipboardMode);
      d.press();
      d.say(20);

      unawaited(
        d.live.service.startTranscription(
          outputEnabled: true,
          serverCommand: LiveServiceHarness.command,
          serverArgs: LiveServiceHarness.args,
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(d.audio.log, isNot(contains('capture.start(output: true)')));
      expect(d.state, isA<DictationTranscribing>());

      d.remote.emitDone('Note rapide.');
      async.elapse(const Duration(seconds: 1));

      expect(d.output.copies, <String>['Note rapide.']);
      final List<String> log = d.audio.log;
      final int meetingCapture = log.indexOf('capture.start(output: true)');
      expect(meetingCapture, greaterThan(0));
      expect(
        log.sublist(0, meetingCapture),
        containsAll(<String>['capture.stop', 'dictation.disconnect']),
      );
      expect(d.live.service.isRecording, isTrue);
    });
  });
}
