import 'dart:async';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart' show InMemoryApiKeyStore;

/// Lectures de la table `summaries` qui échouent ou n'aboutissent pas tant
/// que le test le veut ; le reste de la base marche.
class _Summaries extends QueryInterceptor {
  bool fail = false;
  Completer<void>? hold;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('summaries')) {
      if (fail) throw StateError('base illisible');
      if (hold case final Completer<void> h) await h.future;
    }
    return executor.runSelect(statement, args);
  }
}

/// Page « Coach anglais » de la barre latérale.
///
/// Besoin : la liste, toutes notes confondues (plus récente d'abord), des
/// notes qui ont des corrections, avec leur nombre ; un clic ouvre la note
/// SUR sa section coach (visible même sous un long résumé) ; Retour ramène
/// à la page. Puis les erreurs récurrentes : une même catégorie de
/// correction vue dans 3 notes ou plus (une note compte une fois, quelle
/// que soit le nombre de ses corrections ; « grammar » et « Grammaire » sont
/// la même catégorie, comme dans l'affichage d'une correction). Sans
/// rien : l'état vide en français d'aujourd'hui (`coach.empty`). Chargement
/// et erreur avec une issue (Réessayer) ; une enveloppe abîmée n'empêche
/// pas la liste. Une note dont le coach n'a rien trouvé y figure aussi,
/// avec « Aucune correction » (`coach.no_correction`) pour montrer que la
/// passe a tourné : jours du plus récent au plus ancien ; dans un même
/// jour, sous les notes qui ont des corrections.
///
/// Pas de migration : tout se lit dans `summaries.content` (catégorie déjà
/// présente dans `EnglishCorrectionEntity.category`).
///
/// Application entière (RootAppWidget + vrai routeur), vraie base en
/// mémoire (sessions + enveloppes rangées), note ouverte par
/// `FakeSessionDetailViewModel`.
///
/// Repères supposés (fr.json) : `coach.corrections` (pluriel « {} correction
/// / {} corrections »), `coach.recurring.title`, `coach.recurring.notes`
/// (pluriel « dans {} notes »), libellés de catégorie `coach.category.*`,
/// `common.error.generic` et `common.action.retry` pour l'erreur.
void main() {
  late AppDatabase db;
  late _Summaries interceptor;

  DateTime day(int d) => DateTime(2026, 11, d, 10);

  SessionEntity note(String id, String title, int d) => SessionEntity(
    id: id,
    title: title,
    createdAt: day(d),
    updatedAt: day(d),
    durationSeconds: 1800,
    status: SessionStatus.completed,
  );

  EnglishCorrectionEntity fix(String category, [int i = 0]) =>
      EnglishCorrectionEntity(
        original: 'mistake $category $i',
        corrected: 'better $category $i',
        category: category,
        explanation: 'Raison.',
      );

  final SessionEntity budget = note('budget', 'Point budget', 10);
  final SessionEntity produit = note('produit', 'Revue produit', 14);
  final SessionEntity design = note('design', 'Atelier design', 18);
  final SessionEntity comite = note('comite', 'Comité projet', 20);

  /// Rangé tel quel dans `summaries.content` (null = pas de ligne).
  late Map<String, String?> stored;
  late Map<String, EnglishFeedbackEntity> shownFeedback;

  /// Segments de la note, puis vraie passe du coach d'après l'appel.
  late Map<String, List<TranscriptSegmentEntity>> spoken;

  String envelope(EnglishFeedbackEntity f) =>
      SessionAnalysis(feedback: f).toStored();

  Future<void> pumpApp(
    WidgetTester tester,
    List<SessionEntity> sessions,
  ) async {
    interceptor = _Summaries();
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    addTearDown(db.close);
    final AppFakes fakes = AppFakes(
      sessions: sessions,
      ollama: kOllamaReady,
      detail: (String id) async => SessionDetailState(
        session: sessions.firstWhere((SessionEntity s) => s.id == id),
        segments: const <TranscriptSegmentEntity>[],
        // Long résumé : la section coach est sous la ligne de flottaison.
        summary: List<String>.generate(
          80,
          (int i) => '- Point $i du résumé de la réunion.',
        ).join('\n'),
        feedback: shownFeedback[id],
      ),
    );
    // Un AppFakes par conteneur : un Notifier (ici `AppFakes.live`) ne
    // s'attache qu'à un seul conteneur.
    List<Override> overridesWith(AppFakes f) => <Override>[
      ...f.overrides,
      ...localModelOverrides(db, InstantOllamaService(installed: true)),
      apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
    ];
    final List<Override> overrides = overridesWith(fakes);
    await tester.runAsync(() async {
      final ProviderContainer c = ProviderContainer(
        overrides: overridesWith(
          AppFakes(sessions: sessions, ollama: kOllamaReady),
        ),
      );
      for (final SessionEntity s in sessions) {
        await c.read(sessionRepositoryProvider).create(s);
        if (stored[s.id] case final String content) {
          await c
              .read(summaryServiceProvider)
              .saveSummary(sessionId: s.id, content: content);
        }
        if (spoken[s.id] case final List<TranscriptSegmentEntity> lines) {
          await c.read(transcriptRepositoryProvider).saveBatch(lines);
          // Vraie passe d'après l'appel (`FakeLiveTranscriptionViewModel`
          // ne remplace que build()).
          await c
              .read(liveTranscriptionViewModelProvider.notifier)
              .coachAfterCall(lines, sessionId: s.id);
        }
      }
      c.dispose();
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        child: const RootAppWidget(),
        overrides: overrides,
        withMaterialApp: false,
      ),
    );
    await settle(tester);
  }

  Future<void> io(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settle(tester, frames: 2);
    }
  }

  Finder sidebarItem(String key) => find.descendant(
    of: find.byKey(const ValueKey<String>('oats-sidebar')),
    matching: find.text(key.tr()),
  );

  Future<void> openCoachPage(WidgetTester tester) async {
    await tester.tap(sidebarItem('nav.coach'));
    await io(tester);
  }

  setUp(() {
    stored = <String, String?>{};
    shownFeedback = <String, EnglishFeedbackEntity>{};
    spoken = <String, List<TranscriptSegmentEntity>>{};
  });

  testWidgets('aucune note avec des corrections : l\'état vide en français', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, <SessionEntity>[budget]);

    await openCoachPage(tester);

    expect(find.text('coach.empty'.tr()), findsOneWidget);
  });

  testWidgets('les notes qui ont des corrections, la plus récente d\'abord, '
      'chacune avec son nombre ; les autres n\'y sont pas', (
    WidgetTester tester,
  ) async {
    stored = <String, String?>{
      budget.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[fix('grammar')],
        ),
      ),
      design.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[
            fix('vocabulary', 1),
            fix('vocabulary', 2),
            fix('expression', 3),
          ],
        ),
      ),
      // Résumé seul, sans coach.
      produit.id: const SessionAnalysis(summary: 'Résumé.').toStored(),
    };
    await pumpApp(tester, <SessionEntity>[budget, produit, design]);

    await openCoachPage(tester);

    expect(find.text('Atelier design'), findsOneWidget);
    expect(find.text('Point budget'), findsOneWidget);
    expect(find.text('Revue produit'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Atelier design')).dy,
      lessThan(tester.getTopLeft(find.text('Point budget')).dy),
      reason: 'plus récente d\'abord',
    );
    expect(find.text('coach.corrections'.plural(3)), findsOneWidget);
    expect(find.text('coach.corrections'.plural(1)), findsOneWidget);
    expect(find.text('coach.empty'.tr()), findsNothing);
  });

  testWidgets('une note sans correction figure avec « Aucune correction » : '
      'jours du plus récent au plus ancien, sous les notes corrigées du même '
      'jour', (WidgetTester tester) async {
    SessionEntity at(String id, String title, int d, int hour) => SessionEntity(
      id: id,
      title: title,
      createdAt: DateTime(2026, 11, d, hour),
      updatedAt: DateTime(2026, 11, d, hour),
      durationSeconds: 1800,
      status: SessionStatus.completed,
    );
    final SessionEntity comiteVide = at('comite', 'Comité projet', 20, 9);
    final SessionEntity designVide = at('design', 'Atelier design', 18, 15);
    final SessionEntity produitCorr = at('produit', 'Revue produit', 18, 9);
    final SessionEntity budgetCorr = at('budget', 'Point budget', 10, 9);
    const EnglishFeedbackEntity none = EnglishFeedbackEntity();
    stored = <String, String?>{
      comiteVide.id: envelope(none),
      designVide.id: envelope(none),
      produitCorr.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[fix('grammar')],
        ),
      ),
      budgetCorr.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[fix('vocabulary')],
        ),
      ),
    };
    await pumpApp(tester, <SessionEntity>[
      budgetCorr,
      produitCorr,
      designVide,
      comiteVide,
    ]);

    await openCoachPage(tester);

    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(find.text('coach.no_correction'.tr()), findsNWidgets(2));
    expect(top('Comité projet'), lessThan(top('Revue produit')));
    expect(top('Revue produit'), lessThan(top('Atelier design')));
    expect(top('Atelier design'), lessThan(top('Point budget')));
    expect(find.text('coach.empty'.tr()), findsNothing);
  });

  testWidgets('note sans phrase anglaise de l\'utilisateur (passe faite) : '
      'figure avec « rien en anglais à analyser », pas « Aucune correction »', (
    WidgetTester tester,
  ) async {
    TranscriptSegmentEntity line(String text, AudioSource source) =>
        TranscriptSegmentEntity(
          id: 'design-${text.length}',
          sessionId: design.id,
          source: source,
          text: text,
          timestampMs: 5000,
          createdAt: day(18),
        );
    spoken = <String, List<TranscriptSegmentEntity>>{
      design.id: <TranscriptSegmentEntity>[
        line('Je vous envoie le deck demain.', AudioSource.input),
        line('We need the budget by Friday.', AudioSource.output),
      ],
    };
    await pumpApp(tester, <SessionEntity>[design]);

    await openCoachPage(tester);

    expect(find.text('Atelier design'), findsOneWidget);
    expect(find.text('coach.nothing_to_analyse'.tr()), findsOneWidget);
    expect(find.text('coach.no_correction'.tr()), findsNothing);
  });

  testWidgets('une ligne abîmée parmi d\'autres, dont une d\'avant les '
      'nouveaux champs : les autres notes restent listées', (
    WidgetTester tester,
  ) async {
    stored = <String, String?>{
      budget.id: '{"feedback": {"corrections": [{"original": ',
      produit.id:
          '{"summary": null, "feedback": {"overall": "Bon niveau.", '
          '"corrections": [{"original": "I am agree", "corrected": "I agree", '
          '"category": "grammar", "explanation": "Verbe."}]}, '
          '"micText": null, "speakers": []}',
      design.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[fix('grammar')],
        ),
      ),
    };
    await pumpApp(tester, <SessionEntity>[budget, produit, design]);

    await openCoachPage(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Revue produit'), findsOneWidget);
    expect(find.text('Atelier design'), findsOneWidget);
    expect(find.text('common.error.generic'.tr()), findsNothing);
  });

  testWidgets('une enveloppe abîmée n\'empêche pas la liste', (
    WidgetTester tester,
  ) async {
    stored = <String, String?>{
      budget.id: '{"feedback": {"corrections": [{"original": ',
      design.id: envelope(
        EnglishFeedbackEntity(
          corrections: <EnglishCorrectionEntity>[fix('grammar')],
        ),
      ),
    };
    await pumpApp(tester, <SessionEntity>[budget, design]);

    await openCoachPage(tester);

    expect(find.text('Atelier design'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un clic ouvre la note sur sa section coach, visible même sous '
      'un long résumé ; Retour ramène à la page', (WidgetTester tester) async {
    final EnglishFeedbackEntity fb = EnglishFeedbackEntity(
      corrections: <EnglishCorrectionEntity>[fix('grammar')],
    );
    stored = <String, String?>{design.id: envelope(fb)};
    shownFeedback = <String, EnglishFeedbackEntity>{design.id: fb};
    await pumpApp(tester, <SessionEntity>[design]);
    await openCoachPage(tester);

    await tester.tap(find.text('Atelier design'));
    await io(tester);

    expect(find.byType(SessionDetailScreen), findsOneWidget);
    final Finder coachHeading = find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) => w is Semantics && (w.properties.header ?? false),
      ),
      matching: find.text('history.detail.english_coach'.tr()),
    );
    expect(isOnScreen(coachHeading), isTrue, reason: 'section coach visible');

    await tester.tap(find.byTooltip('common.action.back'.tr()));
    await io(tester);

    expect(find.byType(SessionDetailScreen), findsNothing);
    expect(find.text('Atelier design'), findsOneWidget);
  });

  group('erreurs récurrentes', () {
    testWidgets('une catégorie vue dans 3 notes y figure (grammar = '
        'Grammaire) ; vue dans 2 notes, non ; une note compte une fois', (
      WidgetTester tester,
    ) async {
      stored = <String, String?>{
        budget.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[
              fix('grammar', 1),
              fix('grammar', 2),
              fix('grammar', 3),
              fix('vocabulary', 4),
            ],
          ),
        ),
        produit.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[
              fix('Grammaire', 5),
              fix('vocabulary', 6),
            ],
          ),
        ),
        design.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('grammar', 7)],
          ),
        ),
        comite.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('expression', 8)],
          ),
        ),
      };
      await pumpApp(tester, <SessionEntity>[budget, produit, design, comite]);

      await openCoachPage(tester);

      expect(find.text('coach.recurring.title'.tr()), findsOneWidget);
      expect(find.text('coach.category.grammar'.tr()), findsOneWidget);
      expect(find.text('coach.recurring.notes'.plural(3)), findsOneWidget);
      expect(find.text('coach.recurring.notes'.plural(2)), findsNothing);
    });

    testWidgets('aucune catégorie dans 3 notes : pas de section', (
      WidgetTester tester,
    ) async {
      stored = <String, String?>{
        budget.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('grammar')],
          ),
        ),
        design.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('grammar')],
          ),
        ),
      };
      await pumpApp(tester, <SessionEntity>[budget, design]);

      await openCoachPage(tester);

      expect(find.text('Atelier design'), findsOneWidget);
      expect(find.text('coach.recurring.title'.tr()), findsNothing);
    });
  });

  group('chargement et erreur', () {
    testWidgets('pendant la lecture : un indicateur, pas l\'état vide', (
      WidgetTester tester,
    ) async {
      stored = <String, String?>{
        design.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('grammar')],
          ),
        ),
      };
      await pumpApp(tester, <SessionEntity>[design]);
      interceptor.hold = Completer<void>();

      await openCoachPage(tester);

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('coach.empty'.tr()), findsNothing);
      interceptor.hold!.complete();
      await io(tester);
      expect(find.text('Atelier design'), findsOneWidget);
    });

    testWidgets('lecture impossible : un message et « Réessayer », qui '
        'affiche la liste une fois la base lisible', (
      WidgetTester tester,
    ) async {
      stored = <String, String?>{
        design.id: envelope(
          EnglishFeedbackEntity(
            corrections: <EnglishCorrectionEntity>[fix('grammar')],
          ),
        ),
      };
      await pumpApp(tester, <SessionEntity>[design]);
      interceptor.fail = true;

      await openCoachPage(tester);

      expect(find.text('common.error.generic'.tr()), findsOneWidget);
      expect(find.text('coach.empty'.tr()), findsNothing);

      interceptor.fail = false;
      await tester.tap(find.text('common.action.retry'.tr()));
      await io(tester);

      expect(find.text('Atelier design'), findsOneWidget);
      expect(find.text('common.error.generic'.tr()), findsNothing);
    });
  });
}
