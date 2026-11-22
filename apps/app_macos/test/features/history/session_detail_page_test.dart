import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Détail d'une note : page entière défilable, en-tête (titre, date, durée,
/// interlocuteurs), actions, transcription par tour de parole, suppression
/// confirmée, état « configurer un modèle » quand aucun LLM n'est prêt.
void main() {
  final SessionEntity session = FakeData.createSession(
    id: 's1',
    title: 'Revue trimestrielle',
    createdAt: DateTime(2026, 11, 20, 9, 30),
    updatedAt: DateTime(2026, 11, 20, 10, 37),
    durationSeconds: 67 * 60,
    status: SessionStatus.completed,
  );

  TranscriptSegmentEntity seg(int i, String text, AudioSource source) =>
      TranscriptSegmentEntity(
        id: 'seg-$i',
        sessionId: 's1',
        source: source,
        text: text,
        timestampMs: i * 40000,
        createdAt: DateTime(2026, 11, 20, 9, 30),
      );

  late FakeSessionDetailViewModel vm;
  late int closeCalls;

  Future<void> pumpDetail(
    WidgetTester tester,
    Future<SessionDetailState> Function(String) load, {
    OllamaSetupState ollama = kOllamaReady,
    bool settle = true,
  }) async {
    closeCalls = 0;
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () => closeCalls++),
      settle: settle,
      overrides: <Override>[
        sessionDetailViewModelProvider.overrideWith(() {
          vm = FakeSessionDetailViewModel(load);
          return vm;
        }),
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(ollama),
        ),
      ],
    );
  }

  Future<SessionDetailState> Function(String) state(SessionDetailState s) =>
      (String _) async => s;

  final SessionDetailState simple = SessionDetailState(
    session: session,
    segments: <TranscriptSegmentEntity>[
      seg(0, 'Bonjour à tous.', AudioSource.input),
      seg(1, 'On commence par les chiffres.', AudioSource.input),
      seg(2, 'Très bien, je vous écoute.', AudioSource.output),
      seg(3, 'Le trimestre est bon.', AudioSource.input),
    ],
    speakers: const <SpeakerTurn>[
      SpeakerTurn(speaker: 0, start: 0, end: 4, text: 'Bonjour.'),
      SpeakerTurn(speaker: 1, start: 4, end: 9, text: 'Merci.'),
      SpeakerTurn(speaker: 0, start: 9, end: 12, text: 'Suite.'),
    ],
  );

  testWidgets('toute la page défile : la dernière ligne d\'une longue '
      'transcription devient visible (régression)', (WidgetTester tester) async {
    const String lastLine = 'Dernière phrase de la réunion.';
    final List<TranscriptSegmentEntity> segments = <TranscriptSegmentEntity>[
      for (int i = 0; i < 119; i++)
        seg(
          i,
          'Phrase numéro $i de la transcription.',
          i.isEven ? AudioSource.input : AudioSource.output,
        ),
      seg(119, lastLine, AudioSource.output),
    ];
    // Contenu haut au-dessus de la transcription : c'est lui qui la privait
    // de place quand seule la liste défilait.
    final String longSummary = List<String>.generate(
      40,
      (int i) => 'Point de résumé $i.',
    ).join('\n');
    final List<SpeakerTurn> turns = <SpeakerTurn>[
      for (int i = 0; i < 30; i++)
        SpeakerTurn(
          speaker: i % 2,
          start: i * 10.0,
          end: i * 10.0 + 9,
          text: 'Tour de parole $i.',
        ),
    ];

    await pumpDetail(
      tester,
      state(
        SessionDetailState(
          session: session,
          segments: segments,
          summary: longSummary,
          speakers: turns,
        ),
      ),
    );

    final Finder last = find.text(lastLine);
    final Offset center = tester.getCenter(find.byType(SessionDetailScreen));
    for (int i = 0; i < 80 && !isOnScreen(last); i++) {
      await tester.dragFrom(center, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(isOnScreen(last), isTrue);
    expect(isOnScreen(find.text('Phrase numéro 0 de la transcription.')), isFalse);
  });

  testWidgets('l\'en-tête montre titre, date, durée et les interlocuteurs', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, state(simple));

    expect(find.text('Revue trimestrielle'), findsOneWidget);
    expect(find.textContaining('20 nov'), findsWidgets);
    expect(find.textContaining('1 h 07'), findsOneWidget);

    final Finder chips = find.byKey(const ValueKey<String>('session-detail-speakers'));
    expect(chips, findsOneWidget);
    for (final String n in <String>['1', '2']) {
      expect(
        find.descendant(
          of: chips,
          matching: find.text('history.detail.speaker'.tr(args: <String>[n])),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('les actions Copier, Exporter, Résumer, Coach anglais et '
      'Supprimer restent atteignables', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpDetail(tester, state(simple));

    for (final String key in <String>[
      'history.detail.copy',
      'history.detail.export_markdown',
      'history.detail.summarize',
      'history.detail.english_coach',
      'history.detail.delete',
    ]) {
      final Finder label = find.text(key.tr());
      expect(label.hitTestable(), findsOneWidget, reason: key);
      expect(
        tester.getSemantics(label).getSemanticsData().flagsCollection.isButton,
        isTrue,
        reason: key,
      );
    }
    handle.dispose();
  });

  testWidgets('la transcription est groupée par tour de parole', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, state(simple));

    final Finder transcript = find.byKey(
      const ValueKey<String>('session-detail-transcript'),
    );
    expect(transcript, findsOneWidget);
    Finder inTranscript(Finder f) => find.descendant(of: transcript, matching: f);

    // Micro : 3 phrases en 2 tours (2 consécutives, puis 1 après l'autre
    // voix) → 2 étiquettes « Vous », pas 3. L'étiquette de l'autre voix
    // (source ou interlocuteur diarisé) n'est pas fixée ici.
    expect(
      inTranscript(find.text('history.detail.speaker_me'.tr())),
      findsNWidgets(2),
    );

    final List<double> ys = <String>[
      'Bonjour à tous.',
      'On commence par les chiffres.',
      'Très bien, je vous écoute.',
      'Le trimestre est bon.',
    ].map((String t) => tester.getTopLeft(inTranscript(find.textContaining(t))).dy).toList();
    for (int i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThanOrEqualTo(ys[i - 1]));
    }
  });

  testWidgets('supprimer demande confirmation ; annuler ne supprime rien', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, state(simple));

    await tester.tap(find.text('history.detail.delete'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('history.detail.delete_confirm'.tr()), findsOneWidget);
    expect(vm.deleteCalls, 0);

    await tester.tap(find.text('common.action.cancel'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('history.detail.delete_confirm'.tr()), findsNothing);
    expect(vm.deleteCalls, 0);
    expect(closeCalls, 0);
    expect(find.text('Revue trimestrielle'), findsOneWidget);
  });

  testWidgets('confirmer la suppression supprime et ferme la note', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, state(simple));

    await tester.tap(find.text('history.detail.delete'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(
      // Le bouton de confirmation, dernier « Supprimer » du dialogue.
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.text('common.action.delete'.tr()),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(vm.deleteCalls, 1);
    expect(closeCalls, 1);
  });

  testWidgets('sans modèle prêt : état « configurer un modèle » en ligne, '
      'les actions restent là', (WidgetTester tester) async {
    await pumpDetail(tester, state(simple), ollama: kOllamaAbsent);

    expect(find.textContaining('llm.configure_model'.tr()), findsWidgets);
    expect(find.text('history.detail.summarize'.tr()).hitTestable(), findsOneWidget);
    expect(find.text('Revue trimestrielle'), findsOneWidget);
  });

  testWidgets('avec un modèle prêt : pas d\'invite à configurer', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, state(simple));

    expect(find.text('Revue trimestrielle'), findsOneWidget);
    expect(find.textContaining('llm.configure_model'.tr()), findsNothing);
  });

  testWidgets('pendant le chargement : un indicateur de progression', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (String _) => never(), settle: false);

    expect(
      find.byWidgetPredicate((Widget w) => w is ProgressIndicator),
      findsOneWidget,
    );
    expect(find.text('Revue trimestrielle'), findsNothing);
  });

  testWidgets('en cas d\'erreur : un message lisible', (
    WidgetTester tester,
  ) async {
    await pumpDetail(
      tester,
      (String _) async => throw StateError('base illisible'),
    );

    expect(find.text('common.error.generic'.tr()), findsOneWidget);
  });
}
