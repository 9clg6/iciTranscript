import 'dart:async';
import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// Une ligne `summaries`, plusieurs propriétaires : le résumé, le retour du
/// coach, la transcription propre du micro et les tours de parole vivent
/// dans le même JSON (`SessionAnalysis`), avec une seule colonne `model`.
///
/// Attendu :
/// - résumer garde interlocuteurs, transcription micro et retour du coach ;
/// - écrire le retour du coach (note ou fin d'appel) garde le résumé ET son
///   modèle ;
/// - un résumé interrompu (erreur en cours de flux, note fermée) laisse la
///   ligne précédente intacte, octet pour octet.
void main() {
  late AppDatabase db;
  late ScriptedLlmProvider llm;

  const String oldSummary = 'Résumé précédent : budget validé.';
  const String oldModel = 'claude-ancien-modele';
  const EnglishFeedbackEntity oldFeedback = EnglishFeedbackEntity(
    overall: 'Retour précédent.',
    corrections: <EnglishCorrectionEntity>[
      EnglishCorrectionEntity(
        original: 'I am agree',
        corrected: 'I agree',
        category: 'grammar',
        explanation: 'verbe',
      ),
    ],
  );
  const List<SpeakerTurn> speakers = <SpeakerTurn>[
    SpeakerTurn(speaker: 0, start: 0, end: 4, text: 'Bonjour à tous.'),
    SpeakerTurn(speaker: 1, start: 5, end: 9, text: 'Bonjour.'),
  ];

  Future<ProviderContainer> launch(
    SessionAnalysis existing, {
    String? model,
    required Stream<String> Function(LlmChatRequest r, int i) reply,
  }) async {
    resetPrefs();
    db = memoryDatabase();
    llm = ScriptedLlmProvider(reply);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = RecordingHttpAdapter(),
        ),
        activeLlmProviderProvider.overrideWith((Ref ref) async => llm),
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, kShortMeeting);
    await c
        .read(summaryServiceProvider)
        .saveSummary(
          sessionId: 's1',
          content: existing.toStored(),
          model: model,
        );
    return c;
  }

  Future<SessionDetailViewModelProvider> open(ProviderContainer c) async {
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);
    return note;
  }

  test('résumer garde interlocuteurs, transcription micro et retour du coach',
      () async {
    final ProviderContainer c = await launch(
      const SessionAnalysis(
        feedback: oldFeedback,
        micText: 'I am agree with you.',
        speakers: speakers,
      ),
      reply: (_, _) => Stream<String>.value('Nouveau résumé complet.'),
    );
    final SessionDetailViewModelProvider note = await open(c);

    await c.read(note.notifier).generateSummary();

    final SessionAnalysis saved = await storedAnalysis(db);
    expect(saved.summary, 'Nouveau résumé complet.');
    expect(saved.feedback, oldFeedback);
    expect(saved.micText, 'I am agree with you.');
    expect(saved.speakers.map((SpeakerTurn t) => t.text), <String>[
      'Bonjour à tous.',
      'Bonjour.',
    ]);
  });

  test('coach depuis la note : le résumé et son modèle sont gardés', () async {
    final ProviderContainer c = await launch(
      const SessionAnalysis(summary: oldSummary, speakers: speakers),
      model: oldModel,
      reply: (_, _) => Stream<String>.value(jsonEncode(kFeedbackJson)),
    );
    final SessionDetailViewModelProvider note = await open(c);

    await c.read(note.notifier).analyzeEnglish();

    final SessionAnalysis saved = await storedAnalysis(db);
    expect(saved.feedback?.overall, 'Bon niveau général.');
    expect(saved.summary, oldSummary);
    expect(saved.speakers, hasLength(2));
    expect((await storedRow(db))?.model, oldModel);
  });

  test('coach de fin d\'appel : le résumé et son modèle sont gardés', () async {
    final ProviderContainer c = await launch(
      const SessionAnalysis(summary: oldSummary, speakers: speakers),
      model: oldModel,
      reply: (_, _) => Stream<String>.value(jsonEncode(kFeedbackJson)),
    );

    await c
        .read(liveTranscriptionViewModelProvider.notifier)
        .coachAfterCall('I am agree with you.', sessionId: 's1');

    final SessionAnalysis saved = await storedAnalysis(db);
    expect(saved.feedback?.overall, 'Bon niveau général.');
    expect(saved.summary, oldSummary);
    expect(saved.speakers, hasLength(2));
    expect((await storedRow(db))?.model, oldModel);
  });

  test('résumé interrompu par une erreur en cours de flux : ligne précédente '
      'intacte', () async {
    final ProviderContainer c = await launch(
      const SessionAnalysis(
        summary: oldSummary,
        feedback: oldFeedback,
        speakers: speakers,
      ),
      model: oldModel,
      reply: (_, _) async* {
        yield 'Nouveau résumé, début ';
        throw const LlmUnreachableException('Claude');
      },
    );
    final Summary? before = await storedRow(db);
    final SessionDetailViewModelProvider note = await open(c);

    await c.read(note.notifier).generateSummary();

    final Summary? after = await storedRow(db);
    expect(after?.content, before?.content);
    expect(after?.model, before?.model);
  });

  test('résumé interrompu par la fermeture de la note : ligne précédente '
      'intacte', () async {
    final StreamController<String> answer = StreamController<String>();
    final ProviderContainer c = await launch(
      const SessionAnalysis(summary: oldSummary, feedback: oldFeedback),
      model: oldModel,
      reply: (_, _) => answer.stream,
    );
    final Summary? before = await storedRow(db);
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    final ProviderSubscription<Object?> open = c.listen(note, (_, _) {});
    await c.read(note.future);

    final Future<void> running = c.read(note.notifier).generateSummary();
    await Future<void>.delayed(Duration.zero);
    answer.add('Nouveau résumé, début ');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    open.close(); // la note est fermée
    await Future<void>.delayed(const Duration(milliseconds: 20));
    answer.add('et fin.');
    await answer.close();
    await running.catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final Summary? after = await storedRow(db);
    expect(after?.content, before?.content);
    expect(after?.model, before?.model);
  });
}
