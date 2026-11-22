import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';

/// Résumer et Coach anglais depuis la note : sans modèle local installé,
/// aucun téléchargement silencieux, l'invite « configurer un modèle » à la
/// place ; avec le modèle, ils marchent comme avant. Vrai view model du
/// détail, base Drift en mémoire, Ollama factice.
void main() {
  late AppDatabase db;
  late InstantOllamaService ollama;

  Future<void> pumpNote(WidgetTester tester, {required bool installed}) async {
    ollama = InstantOllamaService(installed: installed);
    db = memoryDatabase();
    addTearDown(db.close);
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(
        overrides: localModelOverrides(db, ollama),
      );
      final DateTime start = DateTime(2026, 11, 20, 9);
      await c.read(sessionRepositoryProvider).create(
        SessionEntity(
          id: 's1',
          title: 'Point anglais',
          createdAt: start,
          updatedAt: start,
          durationSeconds: 600,
          status: SessionStatus.completed,
        ),
      );
      await c.read(transcriptRepositoryProvider).saveBatch(
        <TranscriptSegmentEntity>[
          TranscriptSegmentEntity(
            id: 'seg-1',
            sessionId: 's1',
            source: AudioSource.input,
            text: 'I am agree with you.',
            timestampMs: 0,
            createdAt: start,
          ),
        ],
      );
      c.dispose();
    });
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: <Override>[
        ...localModelOverrides(db, ollama),
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(
            installed ? kOllamaReady : const OllamaSetupState(),
          ),
        ),
      ],
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    await tester.tap(find.text(key.tr()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
  }

  final Finder configure = find.textContaining('llm.configure_model'.tr());

  group('modèle local non installé', () {
    for (final String action in <String>[
      'history.detail.summarize',
      'history.detail.english_coach',
    ]) {
      testWidgets('$action : aucun téléchargement, invite à configurer', (
        WidgetTester tester,
      ) async {
        await pumpNote(tester, installed: false);
        expect(find.text('Point anglais'), findsOneWidget);

        await tapAction(tester, action);

        expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
        expect(ollama.summarizeCalls + ollama.analyzeCalls, 0);
        expect(configure, findsWidgets);
        expect(find.textContaining('Erreur'), findsNothing);
      });
    }
  });

  group('modèle local installé', () {
    testWidgets('Résumer affiche le résumé', (WidgetTester tester) async {
      await pumpNote(tester, installed: true);

      await tapAction(tester, 'history.detail.summarize');

      expect(find.textContaining(InstantOllamaService.summary), findsOneWidget);
      expect(configure, findsNothing);
    });

    testWidgets('Coach anglais affiche le retour', (WidgetTester tester) async {
      await pumpNote(tester, installed: true);

      await tapAction(tester, 'history.detail.english_coach');

      expect(
        find.textContaining(InstantOllamaService.feedback.overall!),
        findsOneWidget,
      );
    });
  });
}
