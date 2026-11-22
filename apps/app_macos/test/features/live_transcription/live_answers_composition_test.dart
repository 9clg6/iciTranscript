import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/live_answers_fakes.dart';
import '../../helpers/live_service_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Composition réelle (T4) : le VRAI view model du direct relie la session à
/// `LiveAnswersService` — démarrage avec l'id de la session, segments finaux
/// transmis, pause, reprise, arrêt. Sans ce lien, toutes les autres specs
/// peuvent passer avec une zone « Questions » morte.
///
/// API supposée : `LiveTranscriptionViewModel` lit `liveAnswersServiceProvider`
/// et appelle `start(sessionId)` au démarrage, `pause()`/`resume()`,
/// `stop()` à l'arrêt, et `onSegmentFinalized` pour chaque segment de
/// `LiveTranscriptionService.finalizedSegmentsStream` (avec l'interlocuteur
/// connu). Serveur, micro, socket et LLM factices ; base en mémoire.
void main() {
  late LiveServiceHarness live;
  late LiveAnswersHarness answers;
  late ProviderContainer c;

  setUp(() {
    resetPrefs();
    live = LiveServiceHarness(FakeAsync());
    answers = LiveAnswersHarness();
    c = ProviderContainer(
      overrides: <Override>[
        liveTranscriptionServiceProvider.overrideWithValue(live.service),
        processManagerServiceProvider.overrideWithValue(
          ProcessManagerService(channel: live.process),
        ),
        audioCaptureChannelProvider.overrideWithValue(DevicesAudioChannel()),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        databaseProvider.overrideWithValue(memoryDatabase()),
        liveAnswersServiceProvider.overrideWithValue(answers.service),
      ],
    );
    addTearDown(c.dispose);
  });

  LiveTranscriptionViewModel vm() =>
      c.read(liveTranscriptionViewModelProvider.notifier);

  // Vraies E/S asynchrones : on attend l'événement, jamais une durée fixe.
  Future<void> say(String text) async {
    live.fakeRemote.emitDone(AudioSource.output, text);
    await eventually(
      () => expect(
        answers.questions.map((LiveQuestion q) => q.text),
        contains(text),
      ),
    );
  }

  Future<void> startSession() async {
    vm();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await vm().startSession();
  }

  test('une question dite pendant la session est détectée, pour cette '
      'session, et sa réponse part', () async {
    await startSession();

    await say('Quand est-ce que vous livrez le lot 1 ?');
    await eventually(() => expect(answers.llm.requests, hasLength(1)));

    expect(answers.questions, hasLength(1));
    expect(
      answers.questions.single.sessionId,
      live.transcription.currentSessionStream.value!.id,
    );
    expect(answers.questions.single.status, LiveQuestionStatus.answering);
    expect(answers.llm.requests, hasLength(1));
  });

  test('en pause rien n\'est détecté ; après la reprise, si', () async {
    await startSession();

    final List<String> finals = <String>[];
    live.service.finalizedSegmentsStream.listen(
      (TranscriptSegmentEntity s) => finals.add(s.text),
    );
    await vm().pauseSession();
    live.fakeRemote.emitDone(
      AudioSource.output,
      'Quand est-ce que vous livrez le lot 1 ?',
    );
    // Finalisée PENDANT la pause (sinon la phrase n'est pas « en pause »).
    await eventually(
      () => expect(finals, contains('Quand est-ce que vous livrez le lot 1 ?')),
    );

    await vm().resumeSession();
    // Même chemin, dans l'ordre : quand la seconde est listée, la première
    // l'aurait été si la pause ne l'avait pas écartée.
    await say('Combien coûte la licence par utilisateur ?');
    expect(answers.questions.map((LiveQuestion q) => q.text), <String>[
      'Combien coûte la licence par utilisateur ?',
    ]);
  });

  test('arrêter la session annule la réponse en vol', () async {
    await startSession();
    await say('Quand est-ce que vous livrez le lot 1 ?');
    await eventually(() => expect(answers.llm.requests, hasLength(1)));
    answers.llm.last.delta('La livr');

    await vm().stopSession();

    await eventually(() => expect(answers.llm.last.cancelled, isTrue));
  });
}
