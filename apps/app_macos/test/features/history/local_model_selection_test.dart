import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// « Modèle local installé » = le modèle choisi pour le fournisseur local
/// dans Réglages (ici [kLocalTestModel], tapé par l'utilisateur), pas
/// seulement `mistral`. S'il manque : invite « configurer un modèle », rien
/// envoyé, rien téléchargé, pas d'échec tardif.
///
/// API supposée : `OllamaService.isInstalled({String? model})` (null =
/// `mistral`) ; le faux [InstantOllamaService] ne connaît que [models].
void main() {
  late AppDatabase db;
  late RecordingHttpAdapter adapter;
  late InstantOllamaService ollama;

  /// Envoi coupé ; modèle local choisi = [kLocalTestModel] sauf si
  /// [defaultModel] ; modèles présents sur le disque = [onDisk].
  List<Override> world(Set<String> onDisk, {bool defaultModel = false}) {
    resetPrefs();
    if (!defaultModel) {
      PrefsStore().update(<String, Object?>{
        LlmSettings.cloudAllowedKey: false,
        LlmSettings.modelsKey: <String, String>{
          LlmProviderId.ollama.name: kLocalTestModel,
        },
      });
    }
    db = memoryDatabase();
    adapter = RecordingHttpAdapter(
      reply: BodyReply(
        200,
        streamOf(LlmProviderId.ollama, 'Le budget est attendu vendredi.'),
      ),
    );
    ollama = InstantOllamaService(installed: true, models: onDisk);
    return <Override>[
      ...localModelOverrides(db, ollama),
      apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
      llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ];
  }

  Future<(ProviderContainer, SessionDetailViewModelProvider)> openNote(
    List<Override> overrides,
  ) async {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...overrides,
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, kShortMeeting);
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);
    return (c, note);
  }

  group('modèle choisi absent (seul mistral est sur le disque)', () {
    test('Résumer : rien envoyé, rien téléchargé, aucun résumé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(world(<String>{'mistral'}));

      await c.read(note.notifier).generateSummary();

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
      expect(c.read(note).value!.summary, isNull);
      expect(c.read(note).value!.summaryError, isNull,
          reason: 'pas d\'échec tardif');
    });

    test('Coach anglais : rien envoyé, rien téléchargé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(world(<String>{'mistral'}));

      await c.read(note.notifier).analyzeEnglish();

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0);
      expect(c.read(note).value!.feedback, isNull);
    });

    test('coach de fin d\'appel : rien envoyé, rien téléchargé', () async {
      final (ProviderContainer c, _) = await openNote(
        world(<String>{'mistral'}),
      );

      await c
          .read(liveTranscriptionViewModelProvider.notifier)
          .coachAfterCall(kShortMeeting, sessionId: 's1');

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0);
      expect(c.read(liveTranscriptionViewModelProvider).feedback, isNull);
    });

    testWidgets('la note invite à configurer un modèle, avant et après '
        'Résumer', (WidgetTester tester) async {
      late List<Override> overrides;
      await tester.runAsync(() async {
        overrides = world(<String>{'mistral'});
        final ProviderContainer c = ProviderContainer(overrides: overrides);
        await seedNote(c, kShortMeeting);
        c.dispose();
      });
      addTearDown(db.close);
      // Vrai OllamaSetupViewModel, branché sur le faux service.
      await pumpLocalized(
        tester,
        SessionDetailScreen(sessionId: 's1', onClose: () {}),
        settle: false,
        overrides: overrides,
      );
      for (int i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await settle(tester, frames: 3);
      }

      expect(find.textContaining('llm.configure_model'.tr()), findsWidgets);

      await tester.tap(find.text('history.detail.summarize'.tr()));
      for (int i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await settle(tester, frames: 3);
      }

      expect(find.textContaining('llm.configure_model'.tr()), findsWidgets);
      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0);
    });
  });

  test('modèle choisi présent : la requête part au modèle local avec ce '
      'modèle', () async {
    final (ProviderContainer c, SessionDetailViewModelProvider note) =
        await openNote(world(<String>{kLocalTestModel}));

    await c.read(note.notifier).generateSummary();

    expect(adapter.lastHost, kProviderHost[LlmProviderId.ollama]);
    expect(adapter.bodies.last?['model'], kLocalTestModel);
    expect(c.read(note).value!.summary, 'Le budget est attendu vendredi.');
  });

  test('aucun modèle choisi et mistral présent : comme avant, le résumé '
      'marche', () async {
    final (ProviderContainer c, SessionDetailViewModelProvider note) =
        await openNote(world(<String>{'mistral'}, defaultModel: true));

    await c.read(note.notifier).generateSummary();

    expect(adapter.lastHost, kProviderHost[LlmProviderId.ollama]);
    expect(c.read(note).value!.summary, 'Le budget est attendu vendredi.');
  });
}
