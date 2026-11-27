import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_presentation/core_presentation.dart' show OatsButton;
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/llm_fakes.dart'
    show noteSegment, seedNote, storedAnalysis, streamOf, writeLlmPrefs;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Transport factice dont la réponse dépend du rang de la requête (0, 1…).
class _ByIndexHttp extends RecordingHttpAdapter {
  _ByIndexHttp(this.replyFor);

  FakeReply Function(int index) replyFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    reply = replyFor(requests.length);
    return super.fetch(options, requestStream, cancelFuture);
  }
}

/// Section « Coach anglais » d'une note.
///
/// Besoin : chaque correction = ce qui a été dit, la meilleure tournure, une
/// raison d'une ligne en français, et l'heure dans la note ; « aucune
/// correction » se dit comme tel, jamais comme une erreur ; une partie non
/// analysée (lot en échec, après l'appel ou à la demande) est signalée par
/// la note, avec « Réessayer » qui ne renvoie QUE ces phrases.
///
/// Vrai `SessionDetailViewModel` + vrai écran, base en mémoire, modèle local
/// installé, transport factice (aucun réseau).
///
/// Hors besoin ici : cliquer l'heure pour aller à la ligne (l'écran de note
/// n'a aucun défilement vers une ligne aujourd'hui : non spécifié) ; l'heure
/// est un texte simple, pas un bouton.
///
/// API supposée : `EnglishCorrectionEntity.timestampMs`,
/// `EnglishFeedbackEntity.unanalyzedSegmentIds` ; heure affichée « mm:ss »
/// comme les tours de la transcription ; textes de fr.json :
/// `coach.unanalyzed` (mention), `common.action.retry` (bouton),
/// `history.detail.coach_perfect` (aucune correction),
/// `coach.nothing_to_analyse` (aucune phrase anglaise de l'utilisateur :
/// rien n'a été envoyé ; ni « Aucune correction » ni erreur). Relancer à
/// la main reprend toutes les phrases (le direct ne fait rien sauter) et
/// remplace le retour. Un retour rangé d'avant les nouveaux champs s'ouvre.
void main() {
  group('une correction affichée', () {
    testWidgets('ce qui a été dit, la meilleure tournure, la raison et '
        'l\'heure dans la note', (WidgetTester tester) async {
      await pumpLocalized(
        tester,
        const CoachFeedbackView(
          feedback: EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[
              EnglishCorrectionEntity(
                original: 'I am agree',
                corrected: 'I agree',
                category: 'grammar',
                explanation: '« agree » est un verbe, sans « am ».',
                timestampMs: 65000,
              ),
            ],
          ),
        ),
      );

      expect(find.textContaining('I am agree'), findsOneWidget);
      expect(find.textContaining('I agree'), findsWidgets);
      expect(find.textContaining('« agree » est un verbe'), findsOneWidget);
      expect(find.textContaining('01:05'), findsOneWidget);
      // Texte simple : l'écran de note ne sait pas aller à une ligne.
      for (final Type tappable in <Type>[InkWell, ButtonStyleButton]) {
        expect(
          find.ancestor(
            of: find.textContaining('01:05'),
            matching: find.byType(tappable),
          ),
          findsNothing,
          reason: 'heure cliquable ($tappable)',
        );
      }
    });

    testWidgets('correction d\'avant (sans heure) : affichée, sans heure '
        'inventée', (WidgetTester tester) async {
      await pumpLocalized(
        tester,
        const CoachFeedbackView(
          feedback: EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[
              EnglishCorrectionEntity(
                original: 'I am agree',
                corrected: 'I agree',
                category: 'grammar',
                explanation: '« agree » est un verbe.',
              ),
            ],
          ),
        ),
      );

      expect(find.textContaining('I am agree'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);
    });

    testWidgets('aucune correction, même avec un commentaire global : '
        '« Aucune correction » affiché', (WidgetTester tester) async {
      await pumpLocalized(
        tester,
        const CoachFeedbackView(
          feedback: EnglishFeedbackEntity(overall: 'Très bon niveau.'),
        ),
      );

      expect(find.text('history.detail.coach_perfect'.tr()), findsOneWidget);
    });
  });

  group('dans la note (vrai view model)', () {
    late AppDatabase db;
    late _ByIndexHttp http;
    late List<Override> overrides;

    String feedbackJson(List<(String, String)> fixes) =>
        jsonEncode(<String, Object?>{
          'overall': 'Bon niveau.',
          'corrections': <Map<String, String>>[
            for (final (String original, String corrected) in fixes)
              <String, String>{
                'original': original,
                'corrected': corrected,
                'category': 'grammar',
                'explanation': 'Explication courte.',
              },
          ],
        });

    FakeReply ok(String json) =>
        BodyReply(200, streamOf(LlmProviderId.ollama, json));

    Future<void> until(WidgetTester tester, bool Function() done) async {
      for (int i = 0; i < 80 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle(tester, frames: 2);
      }
      await settle(tester, frames: 3);
    }

    /// Ouvre la note `s1` (deux appels = la note rouverte : nouveau view
    /// model, relu depuis la base).
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpLocalized(
        tester,
        SessionDetailScreen(sessionId: 's1', onClose: () {}),
        settle: false,
        overrides: overrides,
      );
      await until(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
    }

    /// Note `s1` avec [segments] et, si fourni, le retour [stored] déjà rangé.
    Future<void> seed(
      WidgetTester tester, {
      required List<TranscriptSegmentEntity> segments,
      EnglishFeedbackEntity? stored,
      String? rawStored,
      bool postCall = false,
      required FakeReply Function(int index) replyFor,
    }) async {
      await tester.runAsync(() => writeLlmPrefs(cloudAllowed: false));
      db = memoryDatabase();
      addTearDown(db.close);
      http = _ByIndexHttp(replyFor);
      overrides = <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(kOllamaReady),
        ),
        // Vrai coach d'après l'appel (`coachAfterCall`), sans serveur.
        liveTranscriptionViewModelProvider.overrideWith(
          FakeLiveTranscriptionViewModel.new,
        ),
      ];
      await tester.runAsync(() async {
        final ProviderContainer c = ProviderContainer(overrides: overrides);
        await seedNote(c, segments);
        if (rawStored != null) {
          await c
              .read(summaryServiceProvider)
              .saveSummary(sessionId: 's1', content: rawStored);
        }
        if (postCall) {
          await c
              .read(liveTranscriptionViewModelProvider.notifier)
              .coachAfterCall(segments, sessionId: 's1');
        }
        if (stored != null) {
          await c
              .read(summaryServiceProvider)
              .saveSummary(
                sessionId: 's1',
                content: SessionAnalysis(feedback: stored).toStored(),
              );
        }
        c.dispose();
      });
    }

    Future<EnglishFeedbackEntity?> saved(WidgetTester tester) async =>
        (await tester.runAsync(() => storedAnalysis(db)))!.feedback;

    Finder unanalyzed() => find.text('coach.unanalyzed'.tr());
    Finder retry() => find.text('common.action.retry'.tr());
    // Le bouton de la barre du haut (la section porte le même titre).
    Finder coachAction() =>
        find.widgetWithText(OatsButton, 'history.detail.english_coach'.tr());

    final List<TranscriptSegmentEntity> meeting = <TranscriptSegmentEntity>[
      noteSegment(
        0,
        'I am agree with you on this point.',
        source: AudioSource.input,
      ),
      noteSegment(1, 'We need the budget by Friday.'),
      noteSegment(
        2,
        'He have sent the deck to the client.',
        source: AudioSource.input,
      ),
      noteSegment(
        3,
        'We was ready for the demo yesterday.',
        source: AudioSource.input,
      ),
    ];
    const EnglishCorrectionEntity first = EnglishCorrectionEntity(
      original: 'I am agree',
      corrected: 'I agree',
      category: 'grammar',
      explanation: '« agree » est un verbe.',
      timestampMs: 0,
    );

    testWidgets('note rouverte après un échec partiel : les corrections, la '
        'mention des passages non analysés et « Réessayer »', (
      WidgetTester tester,
    ) async {
      await seed(
        tester,
        segments: meeting,
        stored: const EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[first],
          unanalyzedSegmentIds: <String>['seg-2', 'seg-3'],
        ),
        replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
      );

      await open(tester);

      expect(find.textContaining('I agree'), findsWidgets);
      expect(unanalyzed(), findsOneWidget);
      expect(retry(), findsOneWidget);
      expect(find.text('history.detail.coach_perfect'.tr()), findsNothing);
    });

    testWidgets('rien trouvé mais tout non analysé (échec après l\'appel) : '
        'la mention et « Réessayer », jamais « Aucune correction »', (
      WidgetTester tester,
    ) async {
      await seed(
        tester,
        segments: meeting,
        stored: const EnglishFeedbackEntity(
          unanalyzedSegmentIds: <String>['seg-0', 'seg-2', 'seg-3'],
        ),
        replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
      );

      await open(tester);

      expect(unanalyzed(), findsOneWidget);
      expect(retry(), findsOneWidget);
      expect(find.text('history.detail.coach_perfect'.tr()), findsNothing);
    });

    testWidgets('« Réessayer » ne renvoie que les phrases non analysées ; la '
        'mention disparaît, les corrections s\'ajoutent et sont rangées', (
      WidgetTester tester,
    ) async {
      await seed(
        tester,
        segments: meeting,
        stored: const EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[first],
          unanalyzedSegmentIds: <String>['seg-2', 'seg-3'],
        ),
        replyFor: (_) => ok(
          feedbackJson(<(String, String)>[('He have sent', 'He has sent')]),
        ),
      );
      await open(tester);

      await tester.tap(retry());
      await until(tester, () => unanalyzed().evaluate().isEmpty);

      final String sent = http.bodies.map(jsonEncode).join('\n');
      expect(sent, contains('He have sent the deck'));
      expect(sent, contains('We was ready for the demo'));
      expect(sent, isNot(contains('I am agree with you')));
      expect(sent, isNot(contains('budget by Friday')));
      expect(unanalyzed(), findsNothing);
      expect(find.textContaining('He has sent'), findsWidgets);
      expect(find.textContaining('I agree'), findsWidgets);
      final EnglishFeedbackEntity? after = await saved(tester);
      expect(
        after?.corrections.map((EnglishCorrectionEntity c) => c.corrected),
        unorderedEquals(<String>['I agree', 'He has sent']),
      );
      expect(after?.unanalyzedSegmentIds, isEmpty);
    });

    testWidgets('« Réessayer » échoue encore : la mention reste, les '
        'corrections déjà là aussi', (WidgetTester tester) async {
      await seed(
        tester,
        segments: meeting,
        stored: const EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[first],
          unanalyzedSegmentIds: <String>['seg-2', 'seg-3'],
        ),
        replyFor: (_) => const UnreachableReply(),
      );
      await open(tester);

      await tester.tap(retry());
      // Fin de la nouvelle tentative : requête partie, plus rien en cours.
      await until(
        tester,
        () =>
            http.requests.isNotEmpty &&
            find.text('history.detail.coach_loading'.tr()).evaluate().isEmpty,
      );

      expect(unanalyzed(), findsOneWidget);
      expect(retry(), findsOneWidget);
      expect(find.textContaining('I agree'), findsWidgets);
      final EnglishFeedbackEntity? after = await saved(tester);
      expect(after?.corrections.single.corrected, 'I agree');
      expect(after?.unanalyzedSegmentIds.toSet(), <String>{'seg-2', 'seg-3'});
    });

    testWidgets('« Coach anglais » à la demande sur une longue note, une '
        'partie en échec : corrections montrées, mention, rangé pour la '
        'réouverture', (WidgetTester tester) async {
      final List<TranscriptSegmentEntity> hour = <TranscriptSegmentEntity>[
        for (int i = 0; i < 720; i++)
          noteSegment(
            i,
            'Line $i: we need to check the figures for the next release.',
            source: AudioSource.input,
          ),
      ];
      await seed(
        tester,
        segments: hour,
        replyFor: (int i) => i == 1
            ? const UnreachableReply()
            : ok(
                feedbackJson(<(String, String)>[('phrase $i', 'corrigée $i')]),
              ),
      );
      await open(tester);

      await tester.tap(coachAction());
      await until(tester, () => unanalyzed().evaluate().isNotEmpty);

      expect(http.requests.length, greaterThan(2));
      expect(unanalyzed(), findsOneWidget);
      expect(find.textContaining('corrigée 0'), findsWidgets);
      expect(find.textContaining('llm.error.unreachable'.tr()), findsNothing);

      await open(tester);
      expect(unanalyzed(), findsOneWidget, reason: 'survit à la réouverture');
    });

    testWidgets('« Coach anglais » à la demande, le modèle ne trouve rien : '
        '« Aucune correction », aucune erreur', (WidgetTester tester) async {
      await seed(
        tester,
        segments: meeting,
        replyFor: (_) => ok(
          jsonEncode(<String, Object?>{
            'overall': 'Très bon niveau.',
            'corrections': <Object>[],
          }),
        ),
      );
      await open(tester);

      await tester.tap(coachAction());
      await until(
        tester,
        () => find
            .text('history.detail.coach_perfect'.tr())
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('history.detail.coach_perfect'.tr()), findsOneWidget);
      expect(find.textContaining('llm.error.malformed'.tr()), findsNothing);
      expect(unanalyzed(), findsNothing);
    });

    group('rien en anglais à analyser', () {
      final List<TranscriptSegmentEntity> allFrench = <TranscriptSegmentEntity>[
        noteSegment(
          0,
          'Je pense que le budget est validé pour la semaine.',
          source: AudioSource.input,
        ),
        noteSegment(1, 'We need the budget by Friday.'),
        noteSegment(2, 'On utilise Slack pour ça.', source: AudioSource.input),
      ];
      final List<TranscriptSegmentEntity> noMic = <TranscriptSegmentEntity>[
        noteSegment(0, 'We need the budget by Friday.'),
        noteSegment(1, 'Can you share the slides with the team?'),
      ];

      for (final (String name, List<TranscriptSegmentEntity> segments)
          in <(String, List<TranscriptSegmentEntity>)>[
            ('tout en français', allFrench),
            ('aucune ligne du micro', noMic),
          ]) {
        testWidgets('$name, passe d\'après l\'appel faite : la note dit '
            'qu\'il n\'y avait rien en anglais à analyser, jamais « Aucune '
            'correction »', (WidgetTester tester) async {
          await seed(
            tester,
            segments: segments,
            postCall: true,
            replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
          );

          await open(tester);

          expect(http.requests, isEmpty);
          expect(find.text('coach.nothing_to_analyse'.tr()), findsOneWidget);
          expect(find.text('history.detail.coach_perfect'.tr()), findsNothing);
        });
      }

      testWidgets('« Coach anglais » à la demande sur une note tout en '
          'français : même message, rien n\'est envoyé', (
        WidgetTester tester,
      ) async {
        await seed(
          tester,
          segments: allFrench,
          replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
        );
        await open(tester);

        await tester.tap(coachAction());
        await until(
          tester,
          () =>
              find.text('coach.nothing_to_analyse'.tr()).evaluate().isNotEmpty,
        );

        expect(http.requests, isEmpty);
        expect(find.text('coach.nothing_to_analyse'.tr()), findsOneWidget);
        expect(find.text('history.detail.coach_perfect'.tr()), findsNothing);
      });
    });

    testWidgets('relancer à la main reprend TOUTES les phrases, même celles '
        'corrigées en direct, et remplace leur retour', (
      WidgetTester tester,
    ) async {
      await seed(
        tester,
        segments: meeting,
        // Retour rangé après un direct qui avait corrigé seg-0.
        stored: const EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[first],
        ),
        replyFor: (_) => ok(
          feedbackJson(<(String, String)>[('He have sent', 'He has sent')]),
        ),
      );
      await open(tester);

      await tester.tap(coachAction());
      await until(
        tester,
        () => find.textContaining('He has sent').evaluate().isNotEmpty,
      );

      final String sent = http.bodies.map(jsonEncode).join('\n');
      expect(sent, contains('I am agree with you on this point.'));
      expect(sent, contains('He have sent the deck to the client.'));
      expect(sent, contains('We was ready for the demo yesterday.'));
      expect(
        (await saved(
          tester,
        ))?.corrections.map((EnglishCorrectionEntity c) => c.corrected),
        <String>['He has sent'],
      );
    });

    testWidgets('retour rangé avant ces champs (sans heure ni partie non '
        'analysée) : la note s\'ouvre et le montre', (
      WidgetTester tester,
    ) async {
      await seed(
        tester,
        segments: meeting,
        rawStored: jsonEncode(<String, Object?>{
          'summary': 'Résumé.',
          'feedback': <String, Object?>{
            'overall': 'Bon niveau.',
            'corrections': <Map<String, String>>[
              <String, String>{
                'original': 'I am agree',
                'corrected': 'I agree',
                'category': 'grammar',
                'explanation': '« agree » est un verbe.',
              },
            ],
          },
          'micText': null,
          'speakers': <Object>[],
        }),
        replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
      );

      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('« agree » est un verbe.'), findsOneWidget);
      expect(unanalyzed(), findsNothing);
    });

    testWidgets('note déjà rangée, rouverte : bilan par type et vocabulaire '
        'à retenir, sans relancer le coach', (WidgetTester tester) async {
      Map<String, String> fix(String o, String c, String category) =>
          <String, String>{
            'original': o,
            'corrected': c,
            'category': category,
            'explanation': 'Explication courte.',
          };
      await seed(
        tester,
        segments: meeting,
        rawStored: jsonEncode(<String, Object?>{
          'summary': 'Résumé.',
          'feedback': <String, Object?>{
            'overall': 'Bon niveau.',
            'corrections': <Map<String, String>>[
              fix('I am agree', 'I agree', 'grammar'),
              fix('take a decision', 'make a decision', 'vocabulary'),
              fix('He have sent', 'He has sent', 'grammar'),
            ],
          },
          'micText': null,
          'speakers': <Object>[],
        }),
        replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
      );

      await open(tester);

      final String recap = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('coach-recap')),
              matching: find.byType(RichText),
            ),
          )
          .map((RichText r) => r.text.toPlainText())
          .join(' ');
      expect(
        recap,
        matches(
          RegExp('${coachCategoryLabel('grammar')}[^0-9]*(?<!\\d)2(?!\\d)'),
        ),
      );
      expect(
        recap,
        matches(
          RegExp('${coachCategoryLabel('vocabulary')}[^0-9]*(?<!\\d)1(?!\\d)'),
        ),
      );
      expect(find.text('⟦Vocabulaire à retenir⟧'), findsOneWidget);
      expect(http.requests, isEmpty);
    });
  });
}
