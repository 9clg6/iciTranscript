import 'dart:ui' show Size;

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_answers/question_store.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/services/question_store.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/probe_outputs.dart';
import '../../helpers/settings_fakes.dart' show eventually;

/// « Réponse raccourcie » survit à la réouverture de la note : une réponse
/// raccourcie pendant la réunion (plus de trois puces, sortie réelle du
/// modèle local) garde son signe dans le détail de la note, une fois la
/// note fermée puis rouverte. Vrai `LiveAnswersService`, vrai stockage
/// (`questionStoreProvider` sur une base Drift en mémoire), vrai view model
/// du détail ; seul le LLM est piloté par le test.
///
/// Le signe dans le panneau du direct est déjà fixé par
/// live_answers_panel_test.dart ; ici, seule la réouverture.
void main() {
  late AppDatabase db;
  late InstantOllamaService ollama;
  const String question =
      'Tu as une date pour la recette avec le prestataire ?';

  List<Override> overrides() => <Override>[
    ...localModelOverrides(db, ollama),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
  ];

  /// La réunion : la question arrive, le modèle répond par une sortie
  /// enregistrée de [rawKey] ; la réponse est sauvée comme en direct.
  Future<bool?> meeting(
    WidgetTester tester,
    String rawKey, {
    String? raw,
    List<DocumentExcerpt> excerpts = const <DocumentExcerpt>[],
    void Function(LiveQuestion q)? check,
  }) async {
    return tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides());
      final DateTime start = DateTime(2026, 11, 23, 9);
      await c
          .read(sessionRepositoryProvider)
          .create(
            SessionEntity(
              id: 's1',
              title: 'Point outil de réservation',
              createdAt: start,
              updatedAt: start,
              durationSeconds: 600,
              status: SessionStatus.completed,
            ),
          );
      final QuestionStore store = c.read(questionStoreProvider);
      final ScriptedLlmProvider llm = ScriptedLlmProvider();
      final LiveAnswersService service = LiveAnswersService(
        resolveModel: () async =>
            LiveAnswerModel(provider: llm, modelId: 'claude-haiku-5-5'),
        searchDocuments: (FakeDocumentSearch()..results = excerpts).call,
        store: store,
      )..start('s1');
      service.onSegmentFinalized(
        TranscriptSegmentEntity(
          id: 'seg-1',
          sessionId: 's1',
          source: AudioSource.output,
          text: question,
          timestampMs: 65000,
          createdAt: start,
        ),
        speaker: 0,
      );
      await eventually(() => expect(llm.requests, hasLength(1)));
      llm.last.reply(raw ?? probe(rawKey).raw);
      await eventually(
        () async => expect(
          (await store.forSession('s1')).single.status,
          LiveQuestionStatus.answered,
        ),
      );
      final bool shortened = service.questions.single.shortened;
      check?.call(service.questions.single);
      await service.stop();
      // Note fermée : plus rien en mémoire, seule la base reste.
      c.dispose();
      return shortened;
    });
  }

  Future<void> reopenNote(WidgetTester tester) async {
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

  setUp(() {
    db = memoryDatabase();
    ollama = InstantOllamaService(installed: true);
  });
  tearDown(() => db.close());

  testWidgets(
    'réponse raccourcie : le signe est toujours là à la réouverture',
    (WidgetTester tester) async {
      expect(
        await meeting(tester, 'contract/fr1-c#0'),
        isTrue,
        reason: 'raccourcie pendant la réunion',
      );

      await reopenNote(tester);

      expect(find.text(question), findsOneWidget);
      expect(find.text('live_answers.shortened'.tr()), findsOneWidget);
    },
  );

  testWidgets('réponse courte : pas de signe à la réouverture', (
    WidgetTester tester,
  ) async {
    expect(await meeting(tester, 'contract/en1-a1#0'), isFalse);

    await reopenNote(tester);

    expect(find.text(question), findsOneWidget);
    expect(find.text('live_answers.shortened'.tr()), findsNothing);
  });

  testWidgets('réponse à la fois coupée par la génération et raccourcie : à '
      'la réouverture, la tête reste et au moins un signe d\'incomplétude', (
    WidgetTester tester,
  ) async {
    // Deux blocs : le bloc gardé est celui qui cite l'extrait fourni (donc
    // raccourcie), et sa dernière puce est coupée sur un mot outil
    // (génération arrêtée au milieu d'une phrase).
    const String raw =
        'Planning général\n'
        '- Le pilote démarre en mars.\n'
        '\n'
        'La recette avec le prestataire est prévue après le pilote [S1].\n'
        '- La date reste à confirmer avec le prestataire.\n'
        '- Le bilan sera présenté pour le';
    await meeting(
      tester,
      'contract/fr1-c#0',
      raw: raw,
      excerpts: const <DocumentExcerpt>[
        DocumentExcerpt(
          documentId: 'doc-planning',
          documentTitle: 'Planning du projet',
          text: 'La recette aura lieu après la phase pilote, date à confirmer.',
        ),
      ],
      check: (LiveQuestion q) {
        expect(q.shortened, isTrue, reason: 'raccourcie pendant la réunion');
        expect(q.truncated, isTrue, reason: 'coupée pendant la réunion');
      },
    );

    await reopenNote(tester);

    expect(
      find.textContaining(
        'La recette avec le prestataire est prévue après le pilote',
      ),
      findsOneWidget,
    );
    final int signs =
        find.text('live_answers.shortened'.tr()).evaluate().length +
        find.text('live_answers.truncated'.tr()).evaluate().length;
    expect(signs, greaterThanOrEqualTo(1));
  });
}
