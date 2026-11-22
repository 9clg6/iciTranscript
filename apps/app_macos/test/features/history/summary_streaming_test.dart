import 'dart:async';
import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Résumé et coach dans la note (besoin B9) : le texte arrive au fil de
/// l'eau, les erreurs typées ont un message clair, une réponse tronquée ou
/// refusée est montrée telle quelle et signalée au lieu d'être rangée comme
/// un résumé complet, une sortie mal formée ne fait jamais planter.
///
/// Monde de test : modèle local installé, envoi coupé, et
/// `activeLlmProviderProvider` (type inchangé : `Future<LlmProvider>`)
/// remplacé par un fournisseur scripté.
///
/// Règle « tronquée » retenue (zone grise signalée au rapport) : flux vide,
/// ou dernière ligne non vide qui n'est ni une puce ni un intertitre et ne
/// finit pas par . ! ? … » ou ). Une liste à puces sans point final est
/// complète.
void main() {
  late AppDatabase db;
  late ScriptedLlmProvider llm;

  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await settle(tester, frames: 3);
    }
  }

  List<Override> overrides() => <Override>[
    ...localModelOverrides(db, InstantOllamaService(installed: true)),
    apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
    llmDioProvider.overrideWithValue(
      Dio()..httpClientAdapter = RecordingHttpAdapter(),
    ),
    activeLlmProviderProvider.overrideWith((Ref ref) async => llm),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(kOllamaReady),
    ),
  ];

  Future<void> openScreen(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      settle: false,
      overrides: overrides(),
    );
    await idle(tester);
  }

  /// Note `s1` (réunion courte) et fournisseur répondant par [reply].
  Future<void> pumpNote(
    WidgetTester tester,
    Stream<String> Function(LlmChatRequest r, int i) reply,
  ) async {
    resetPrefs();
    db = memoryDatabase();
    addTearDown(db.close);
    llm = ScriptedLlmProvider(reply);
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(overrides: overrides());
      await seedNote(c, kShortMeeting);
      c.dispose();
    });
    await openScreen(tester);
  }

  /// Rouvre la note : nouveau view model, relu depuis la base.
  Future<void> reopen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await openScreen(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    await tester.tap(find.text(key.tr()));
    await idle(tester);
  }

  Finder incomplete() => find.textContaining('llm.incomplete'.tr());

  group('au fil de l\'eau', () {
    testWidgets('le premier morceau s\'affiche tout de suite, la suite '
        's\'ajoute, le résumé fini est rangé', (WidgetTester tester) async {
      final StreamController<String> answer = StreamController<String>();
      await pumpNote(tester, (_, _) => answer.stream);

      await tapAction(tester, 'history.detail.summarize');
      answer.add('Contexte : point sur le budget.');
      await idle(tester);

      expect(
        find.textContaining('Contexte : point sur le budget.'),
        findsOneWidget,
        reason: 'premier morceau visible avant la fin du flux',
      );

      answer.add('\n- Décision : budget validé.');
      await idle(tester);
      expect(find.textContaining('Décision : budget validé.'), findsOneWidget);

      await answer.close();
      await idle(tester);

      expect(incomplete(), findsNothing);
      expect(
        (await tester.runAsync(() => storedAnalysis(db)))!.summary,
        'Contexte : point sur le budget.\n- Décision : budget validé.',
      );
    });
  });

  group('erreurs typées', () {
    final Map<String, Object> errors = <String, Object>{
      'llm.error.invalid_key': const LlmInvalidKeyException('Claude'),
      'llm.error.rate_limited': const LlmRateLimitedException('Claude'),
      'llm.error.unreachable': const LlmUnreachableException('Ollama'),
      'llm.error.failed': const FormatException('ligne JSON invalide'),
    };
    errors.forEach((String key, Object error) {
      testWidgets('${error.runtimeType} : message « $key », rien rangé comme '
          'résumé', (WidgetTester tester) async {
        await pumpNote(tester, (_, _) => Stream<String>.error(error));

        await tapAction(tester, 'history.detail.summarize');

        expect(tester.takeException(), isNull);
        expect(find.textContaining(key.tr()), findsOneWidget);
        expect(
          (await tester.runAsync(() => storedAnalysis(db)))!.summary,
          isNull,
        );
      });
    });

    testWidgets('l\'erreur après un début de réponse ne range pas ce début '
        'comme résumé', (WidgetTester tester) async {
      await pumpNote(
        tester,
        (_, _) async* {
          yield 'Contexte : point sur ';
          throw const LlmUnreachableException('Claude');
        },
      );

      await tapAction(tester, 'history.detail.summarize');

      expect(find.textContaining('llm.error.unreachable'.tr()), findsOneWidget);
      expect(
        (await tester.runAsync(() => storedAnalysis(db)))!.summary,
        isNull,
      );
    });
  });

  group('réponse tronquée ou refusée (fin sans erreur)', () {
    Future<void> expectFlaggedNotComplete(
      WidgetTester tester,
      String? fragment,
    ) async {
      expect(incomplete(), findsOneWidget);
      if (fragment != null) {
        expect(find.textContaining(fragment), findsOneWidget,
            reason: 'montrée telle quelle');
      }
      await reopen(tester);
      if (fragment != null &&
          find.textContaining(fragment).evaluate().isNotEmpty) {
        expect(incomplete(), findsOneWidget,
            reason: 'rouverte, elle reste signalée');
      }
    }

    testWidgets('flux vide : signalé, aucun résumé complet', (
      WidgetTester tester,
    ) async {
      await pumpNote(tester, (_, _) => const Stream<String>.empty());

      await tapAction(tester, 'history.detail.summarize');

      await expectFlaggedNotComplete(tester, null);
      expect(
        (await tester.runAsync(() => storedAnalysis(db)))!.summary,
        anyOf(isNull, isEmpty),
      );
    });

    testWidgets('fin au milieu d\'une phrase : montrée telle quelle et '
        'signalée', (WidgetTester tester) async {
      await pumpNote(
        tester,
        (_, _) => Stream<String>.fromIterable(<String>[
          'Contexte : la réunion porte sur le budget.\n',
          'Les participants ont décidé que le budget sera de',
        ]),
      );

      await tapAction(tester, 'history.detail.summarize');

      await expectFlaggedNotComplete(tester, 'le budget sera de');
    });

    testWidgets('liste à puces sans point final : complète, pas signalée', (
      WidgetTester tester,
    ) async {
      const String full =
          'Contexte : point budget.\n- Valider le budget\n- Relancer le fournisseur';
      await pumpNote(tester, (_, _) => Stream<String>.value(full));

      await tapAction(tester, 'history.detail.summarize');

      expect(incomplete(), findsNothing);
      expect((await tester.runAsync(() => storedAnalysis(db)))!.summary, full);
    });
  });

  group('sortie mal formée', () {
    testWidgets('résumé au Markdown cassé : affiché sans planter', (
      WidgetTester tester,
    ) async {
      await pumpNote(
        tester,
        (_, _) => Stream<String>.value('**\n#\n- \n```\n{"\n1.\n***gras**.'),
      );

      await tapAction(tester, 'history.detail.summarize');

      expect(tester.takeException(), isNull);
      expect(llm.requests, isNotEmpty);
      expect(find.textContaining('gras'), findsWidgets);
    });

    final Map<String, String> badFeedback = <String, String>{
      'du texte au lieu du JSON': 'Voici mon analyse : très bon niveau !',
      'un JSON coupé': '{"overall": "Bon niv',
      'un JSON d\'une autre forme': '{"corrections": "aucune"}',
    };
    badFeedback.forEach((String name, String reply) {
      testWidgets('coach : $name ne fait pas planter, message clair', (
        WidgetTester tester,
      ) async {
        await pumpNote(tester, (_, _) => Stream<String>.value(reply));

        await tapAction(tester, 'history.detail.english_coach');

        expect(tester.takeException(), isNull);
        expect(find.textContaining('llm.error.malformed'.tr()), findsOneWidget);
      });
    });

    testWidgets('coach : JSON entouré d\'un bloc ```json (fréquent chez les '
        'modèles en ligne) est lu', (WidgetTester tester) async {
      const Map<String, Object?> fenced = <String, Object?>{
        'overall': 'Niveau solide.',
        'corrections': <Map<String, String>>[
          <String, String>{
            'original': 'I work here since 2020',
            'corrected': 'I have been working here since 2020',
            'category': 'conjugation',
            'explanation': 'Present perfect continu avec « since ».',
          },
        ],
      };
      await pumpNote(
        tester,
        (_, _) => Stream<String>.value(
          'Voici le retour :\n```json\n${jsonEncode(fenced)}\n```',
        ),
      );

      await tapAction(tester, 'history.detail.english_coach');

      expect(find.textContaining('I have been working here'), findsWidgets);
      expect(find.textContaining('llm.error.malformed'.tr()), findsNothing);
    });

    testWidgets('coach : erreur typée = message clair', (
      WidgetTester tester,
    ) async {
      await pumpNote(
        tester,
        (_, _) => Stream<String>.error(const LlmInvalidKeyException('Claude')),
      );

      await tapAction(tester, 'history.detail.english_coach');

      expect(find.textContaining('llm.error.invalid_key'.tr()), findsOneWidget);
    });
  });
}
