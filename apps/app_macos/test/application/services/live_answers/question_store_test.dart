import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_answers/question_store.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/services/question_store.provider.dart';
import 'package:ici_transcript/core/providers/services/session_history.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';

import '../../../helpers/local_model_fakes.dart';

/// Questions et réponses gardées avec la note (T4, besoin 9) : vraie base
/// Drift en mémoire, vrai stockage, vrai view model du détail.
///
/// API supposée :
/// - lib/application/services/live_answers/question_store.dart :
///   `abstract interface class QuestionStore` avec
///   `Future<void> saveDetected(LiveQuestion q)`,
///   `Future<void> saveAnswer(LiveQuestion q)` (réponse, modèle, sources),
///   `Future<void> delete(String questionId)`,
///   `Future<List<LiveQuestion>> forSession(String sessionId)`.
/// - lib/core/providers/services/question_store.provider.dart :
///   `questionStoreProvider` (sur `databaseProvider`, via `DetectedQuestionDao`).
/// - `SessionDetailState.questions` : `List<LiveQuestion>`, défaut vide,
///   chargé par `SessionDetailViewModel.build`.
/// - Relue : question avec réponse = `answered` ; sans réponse = `detected`,
///   `answer` vide.
/// - `LiveQuestion({required String id, required String sessionId, String? segmentId, required String text, AudioSource source = AudioSource.output, int? speaker, required int timestampMs, LiveQuestionStatus status = LiveQuestionStatus.detected, String answer = '', bool truncated = false, LiveAnswerFailure? failure, List<AnswerSource> sources = const <AnswerSource>[], String? model})`.
void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    db = memoryDatabase();
    c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        databaseProvider.overrideWithValue(db),
      ],
    );
    final DateTime start = DateTime(2026, 11, 22, 10);
    await c
        .read(sessionRepositoryProvider)
        .create(
          SessionEntity(
            id: 's1',
            title: 'Point client',
            createdAt: start,
            updatedAt: start,
            durationSeconds: 600,
            status: SessionStatus.completed,
          ),
        );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  QuestionStore store() => c.read(questionStoreProvider);

  const LiveQuestion detected = LiveQuestion(
    id: 'q1',
    sessionId: 's1',
    segmentId: 'seg-7',
    text: 'Est-ce que vous avez prévu une date de livraison ?',
    speaker: 1,
    timestampMs: 65000,
  );
  const AnswerSource source = AnswerSource(
    documentId: 'doc-1',
    title: 'Contrat Acme 2026',
    excerpt: 'Livraison du lot 1 le 12 mars 2026.',
  );

  test('une question sauvée à la détection se relit sans réponse', () async {
    await store().saveDetected(detected);

    final LiveQuestion q = (await store().forSession('s1')).single;
    expect(q.id, 'q1');
    expect(q.segmentId, 'seg-7');
    expect(q.text, detected.text);
    expect(q.timestampMs, 65000);
    expect(q.answer, isEmpty);
    expect(q.status, LiveQuestionStatus.detected);
  });

  test(
    'la réponse, le modèle et les sources se relisent à l\'identique',
    () async {
      await store().saveDetected(detected);
      await store().saveAnswer(
        const LiveQuestion(
          id: 'q1',
          sessionId: 's1',
          segmentId: 'seg-7',
          text: 'Est-ce que vous avez prévu une date de livraison ?',
          timestampMs: 65000,
          status: LiveQuestionStatus.answered,
          answer: 'Le lot 1 arrive le 12 mars.',
          model: 'claude-haiku-5-5',
          sources: <AnswerSource>[source],
        ),
      );

      final LiveQuestion q = (await store().forSession('s1')).single;
      expect(q.status, LiveQuestionStatus.answered);
      expect(q.answer, 'Le lot 1 arrive le 12 mars.');
      expect(q.model, 'claude-haiku-5-5');
      expect(q.sources, <AnswerSource>[source]);
    },
  );

  test('la note rouverte plus tard montre ses questions et réponses', () async {
    await store().saveDetected(detected);
    await store().saveAnswer(
      const LiveQuestion(
        id: 'q1',
        sessionId: 's1',
        text: 'Est-ce que vous avez prévu une date de livraison ?',
        timestampMs: 65000,
        status: LiveQuestionStatus.answered,
        answer: 'Le lot 1 arrive le 12 mars.',
        model: 'claude-haiku-5-5',
      ),
    );

    final SessionDetailState state = await c.read(
      sessionDetailViewModelProvider(sessionId: 's1').future,
    );

    expect(state.questions.single.text, detected.text);
    expect(state.questions.single.answer, 'Le lot 1 arrive le 12 mars.');
  });

  test('« Ignorer » supprime la question sauvée', () async {
    await store().saveDetected(detected);
    await store().delete('q1');

    expect(await store().forSession('s1'), isEmpty);
  });

  test('garde : supprimer la note supprime ses questions', () async {
    await store().saveDetected(detected);

    await c.read(sessionHistoryServiceProvider).deleteSession('s1');

    expect(await store().forSession('s1'), isEmpty);
  });
}
