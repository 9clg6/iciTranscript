import 'dart:ui' show Size;

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/detected_question.dao.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';

/// Une question rangée avec un `status` que ce build ne connaît pas (écrit
/// par une version plus récente) : avec un texte de réponse, elle se lit
/// comme une réponse simple (sans signe, avec ses sources) ; sans texte de
/// réponse, comme une question sans réponse (jamais une « réponse » vide).
/// Rien ne plante. Vrai stockage (Drift en mémoire) jusqu'au détail de note.
void main() {
  late AppDatabase db;
  late InstantOllamaService ollama;
  const String withAnswer = 'Quel est le préavis du contrat d\'hébergement ?';
  const String withoutAnswer = 'Combien coûte la licence par utilisateur ?';

  List<Override> overrides() => <Override>[
    ...localModelOverrides(db, ollama),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
  ];

  setUp(() {
    db = memoryDatabase();
    ollama = InstantOllamaService(installed: true);
  });
  tearDown(() => db.close());

  Future<void> storeRows(WidgetTester tester) => tester.runAsync(() async {
    final ProviderContainer c = ProviderContainer(overrides: overrides());
    final DateTime start = DateTime(2026, 11, 23, 9);
    await c
        .read(sessionRepositoryProvider)
        .create(
          SessionEntity(
            id: 's1',
            title: 'Point contrat',
            createdAt: start,
            updatedAt: start,
            durationSeconds: 600,
            status: SessionStatus.completed,
          ),
        );
    c.dispose();
    final DetectedQuestionDao dao = DetectedQuestionDao(db);
    await dao.insertDetected(
      id: 'q1',
      sessionId: 's1',
      question: withAnswer,
      timestampMs: 60000,
      createdAt: start,
      source: 'output',
      speaker: '0',
    );
    await dao.saveAnswer(
      'q1',
      answer: 'Le préavis est de 90 jours. [S1]',
      model: 'claude-haiku-5-5',
      sources: const <StoredAnswerSource>[
        (
          documentId: 'doc-contrat',
          title: 'Contrat d\'hébergement',
          excerpt: 'Chaque partie peut résilier avec un préavis de 90 jours.',
        ),
      ],
    );
    await dao.insertDetected(
      id: 'q2',
      sessionId: 's1',
      question: withoutAnswer,
      timestampMs: 120000,
      createdAt: start,
      source: 'output',
    );
    // Valeur écrite par une version future.
    await db.customStatement(
      "UPDATE detected_questions SET status = 'reviewed_by_user_v9'",
    );
  });

  Future<void> openNote(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      size: const Size(1280, 3000),
      settle: false,
      overrides: overrides(),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
  }

  testWidgets('avec réponse : réponse simple, sans signe, avec sa source', (
    WidgetTester tester,
  ) async {
    await storeRows(tester);
    await openNote(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(withAnswer), findsOneWidget);
    expect(find.textContaining('Le préavis est de 90 jours.'), findsOneWidget);
    expect(find.textContaining('Contrat d\'hébergement'), findsWidgets);
    for (final String sign in <String>[
      'live_answers.shortened',
      'live_answers.truncated',
      'live_answers.declined',
      'history.detail.answer_failed',
    ]) {
      expect(find.text(sign.tr()), findsNothing, reason: sign);
    }
  });

  testWidgets('sans réponse : « Sans réponse », jamais une réponse vide', (
    WidgetTester tester,
  ) async {
    await storeRows(tester);
    await openNote(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(withoutAnswer), findsOneWidget);
    expect(find.text('history.detail.no_answer'.tr()), findsOneWidget);
  });
}
