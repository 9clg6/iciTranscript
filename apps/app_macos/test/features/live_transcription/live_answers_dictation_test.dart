import 'dart:io';

import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
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

/// Dictée pendant une réunion × questions en direct (T2 × T4) : les mots
/// dictés au micro (raccourci tenu, de l'appui au relâchement, annulation
/// comprise) n'atteignent jamais la porte ni le contexte d'une question ;
/// l'audio système pendant ce temps est traité normalement.
///
/// Une seule décision, un seul endroit : la source de vérité est celle de la
/// dictée, `LiveTranscriptionService.beginDictation()` → `MeetingDictation`
/// (`release()`, `cancel()`), qui route les `done` micro de l'intervalle vers
/// la dictée au lieu de la note ; ils ne sont donc jamais émis sur
/// `finalizedSegmentsStream`, seule entrée de `LiveAnswersService`.
/// À GARDER : `beginDictation` / `MeetingDictation`, `finalizedSegmentsStream`,
/// `DictatedIntervalsStore` (pour les passes après la réunion).
/// À SUPPRIMER : `LiveAnswersService.markDictation` et tout filtre de dictée
/// propre aux questions (second marqueur sans appelant).
///
/// Vrai view model du direct, vrai `LiveTranscriptionService` ; faux :
/// serveur, micro, socket (le test joue le serveur), LLM.
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

  Future<void> later() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  Future<void> startMeeting() async {
    c.read(liveTranscriptionViewModelProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await c.read(liveTranscriptionViewModelProvider.notifier).startSession();
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  /// Phrase finale du micro, parole entre [startMs] et [endMs] (ms epoch,
  /// horloge de la capture).
  Future<void> mic(String text, {int? startMs, int? endMs}) async {
    live.fakeRemote.emitDone(
      AudioSource.input,
      text,
      window: startMs == null
          ? null
          : UtteranceWindow(startMs: startMs, endMs: endMs ?? startMs + 40),
    );
    await later();
  }

  Future<void> others(String text) async {
    live.fakeRemote.emitDone(AudioSource.output, text);
    await later();
  }

  String lastRequest() => requestText(answers.llm.last.request);

  const String q = 'Est-ce que vous avez prévu une date de livraison ?';

  test('raccourci tenu : la phrase micro dictée n\'est pas dans le contexte, '
      'la question des autres dite pendant ce temps est détectée', () async {
    await startMeeting();
    final int pressAt = now();
    final MeetingDictation? d = live.service.beginDictation();
    expect(d, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await mic('DICTATED-HELD rappelle le fournisseur', startMs: pressAt + 50);
    await others(q);

    expect(answers.questions.map((LiveQuestion x) => x.text), <String>[q]);
    expect(lastRequest(), isNot(contains('DICTATED-HELD')));
    d!.release();
  });

  test('phrase dont le `done` arrive après le relâchement mais dont l\'audio '
      'est dans l\'intervalle : exclue aussi', () async {
    await startMeeting();
    final int pressAt = now();
    final MeetingDictation d = live.service.beginDictation()!;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    d.release();

    await mic(
      'DICTATED-LATE envoie le devis',
      startMs: pressAt + 50,
      endMs: pressAt + 120,
    );
    await others(q);

    expect(lastRequest(), isNot(contains('DICTATED-LATE')));
    expect(answers.questions.single.text, q);
  });

  test('dictée annulée (Échap) : ses mots sont exclus aussi', () async {
    await startMeeting();
    final int pressAt = now();
    final MeetingDictation d = live.service.beginDictation()!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await mic('DICTATED-CANCELLED mot de passe', startMs: pressAt + 50);
    d.cancel();

    await others(q);

    expect(lastRequest(), isNot(contains('DICTATED-CANCELLED')));
  });

  test('une phrase dictée qui est une question ne devient jamais une '
      'question, même posée à la main', () async {
    await startMeeting();
    final int pressAt = now();
    final MeetingDictation d = live.service.beginDictation()!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await mic(
      'Est-ce que DICTATED-QUESTION part au modèle ?',
      startMs: pressAt + 50,
    );
    d.release();

    answers.service.answerLatestFromOthers();
    await later();

    expect(answers.questions, isEmpty);
    expect(answers.llm.requests, isEmpty);
  });

  test('après le relâchement, le micro revient au contexte', () async {
    await startMeeting();
    final int pressAt = now();
    final MeetingDictation d = live.service.beginDictation()!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    d.release();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await mic('CTX-AFTER on reprend le planning', startMs: pressAt + 400);
    await others(q);

    expect(lastRequest(), contains('CTX-AFTER'));
  });

  test(
    'garde : sans dictée, rien ne change (le micro est dans le contexte)',
    () async {
      await startMeeting();

      await mic('CTX-MIC on a fini la recette.', startMs: now());
      await others(q);

      expect(lastRequest(), contains('CTX-MIC'));
      expect(answers.questions.single.text, q);
      final String id = live.transcription.currentSessionStream.value!.id;
      expect(
        File(
          '${LiveTranscriptionService.recordingsDir}/${id}_dictations.json',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('une seule décision : les questions n\'ont pas leur propre filtre de '
      'dictée', () {
    final Iterable<File> files =
        Directory('lib/application/services/live_answers')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'));
    for (final File f in files) {
      final String src = f.readAsStringSync();
      expect(src, isNot(contains('markDictation')), reason: f.path);
      expect(src, isNot(contains('DictatedInterval')), reason: f.path);
    }
  });
}
