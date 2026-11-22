import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Section « Questions posées » de la note (T4, besoins 9 et 11) : les
/// questions de la réunion avec la réponse gardée et ses sources.
///
/// API supposée : `SessionDetailState.questions` (`List<LiveQuestion>`,
/// défaut vide). Choix : sans question, la section n'apparaît pas.
void main() {
  final SessionEntity session = FakeData.createSession(
    id: 's1',
    title: 'Point client',
    createdAt: DateTime(2026, 11, 20, 9, 30),
    updatedAt: DateTime(2026, 11, 20, 10, 0),
    durationSeconds: 30 * 60,
    status: SessionStatus.completed,
  );
  final List<TranscriptSegmentEntity> segments = <TranscriptSegmentEntity>[
    TranscriptSegmentEntity(
      id: 'seg-1',
      sessionId: 's1',
      source: AudioSource.output,
      text: 'Bonjour, est-ce que vous avez prévu une date de livraison ?',
      timestampMs: 65000,
      createdAt: DateTime(2026, 11, 20, 9, 31),
    ),
  ];

  const LiveQuestion answered = LiveQuestion(
    id: 'q1',
    sessionId: 's1',
    segmentId: 'seg-1',
    text: 'Est-ce que vous avez prévu une date de livraison ?',
    speaker: 1,
    timestampMs: 65000,
    status: LiveQuestionStatus.answered,
    answer: 'Le lot 1 arrive le 12 mars.',
    model: 'claude-haiku-5-5',
    sources: <AnswerSource>[
      AnswerSource(
        documentId: 'doc-contract',
        title: 'Contrat Acme 2026',
        excerpt: 'Livraison du lot 1 le 12 mars 2026.',
      ),
    ],
  );
  const LiveQuestion unanswered = LiveQuestion(
    id: 'q2',
    sessionId: 's1',
    text: 'Combien coûte la licence par utilisateur ?',
    timestampMs: 120000,
  );

  Future<void> pumpNote(WidgetTester tester, List<LiveQuestion> questions) =>
      pumpLocalized(
        tester,
        SessionDetailScreen(sessionId: 's1', onClose: () {}),
        size: const Size(1280, 3000),
        overrides: <Override>[
          sessionDetailViewModelProvider.overrideWith(
            () => FakeSessionDetailViewModel(
              (String _) async => SessionDetailState(
                session: session,
                segments: segments,
                questions: questions,
              ),
            ),
          ),
          ollamaSetupViewModelProvider.overrideWith(
            () => FakeOllamaSetupViewModel(kOllamaReady),
          ),
        ],
      );

  testWidgets('les questions posées, avec la réponse gardée et sa source', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, const <LiveQuestion>[answered]);

    expect(find.text('history.detail.questions'.tr()), findsOneWidget);
    expect(find.text(answered.text), findsOneWidget);
    expect(find.textContaining('Le lot 1 arrive le 12 mars.'), findsOneWidget);
    expect(find.textContaining('Contrat Acme 2026'), findsOneWidget);
  });

  testWidgets('une question restée sans réponse le dit', (
    WidgetTester tester,
  ) async {
    await pumpNote(tester, const <LiveQuestion>[answered, unanswered]);

    expect(find.text(unanswered.text), findsOneWidget);
    expect(find.text('history.detail.no_answer'.tr()), findsOneWidget);
  });

  testWidgets('sans question, pas de section', (WidgetTester tester) async {
    await pumpNote(tester, const <LiveQuestion>[]);

    expect(find.text('history.detail.questions'.tr()), findsNothing);
  });
}
