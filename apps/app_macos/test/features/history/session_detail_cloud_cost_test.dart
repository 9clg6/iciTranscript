import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Prix de la transcription en ligne (2026-11-26) : la fiche d'une note
/// transcrite par Mistral montre une puce avec le prix estimé, en USD,
/// format français : « ≈ 0,01 $ » ; sous 0,01 $ : « < 0,01 $ ». Une
/// infobulle dit qu'il s'agit de la transcription Mistral seule (le résumé
/// n'est pas compris). Note locale (aucun audio envoyé) : pas de puce.
///
/// Prix = minutes temps réel × 0,008 $ + minutes batch × 0,0035 $
/// (cloud_transcription_cost_test.dart, core_domain). Montants choisis loin
/// des demi-centimes. Libellé et infobulle passent par fr.json (marqués
/// ⟦…⟧ dans les tests) ; une espace insécable est admise autour du nombre.
///
/// API supposée : `SessionEntity.cloudRealtimeMs`, `cloudBatchMs` (int,
/// défaut 0), lus par l'écran depuis `SessionDetailState.session`.
void main() {
  SessionEntity session({int realtimeMs = 0, int batchMs = 0}) => SessionEntity(
    id: 's1',
    title: 'Point équipe',
    createdAt: DateTime(2026, 11, 26, 9),
    updatedAt: DateTime(2026, 11, 26, 10),
    durationSeconds: 3600,
    status: SessionStatus.completed,
    cloudRealtimeMs: realtimeMs,
    cloudBatchMs: batchMs,
  );

  Future<void> pump(WidgetTester tester, SessionEntity s) => pumpLocalized(
    tester,
    SessionDetailScreen(sessionId: 's1', onClose: () {}),
    overrides: <Override>[
      sessionDetailViewModelProvider.overrideWith(
        () => FakeSessionDetailViewModel(
          (String _) async => SessionDetailState(
            session: s,
            segments: const <TranscriptSegmentEntity>[],
          ),
        ),
      ),
      ollamaSetupViewModelProvider.overrideWith(
        () => FakeOllamaSetupViewModel(kOllamaReady),
      ),
    ],
  );

  /// Un montant en dollars, quel qu'il soit.
  final RegExp anyPrice = RegExp(r'[≈<]\s?\d+,\d{2}\s?\$');

  Finder tooltip() => find.byWidgetPredicate(
    (Widget w) =>
        w is Tooltip &&
        (w.message ?? '').contains('Mistral') &&
        (w.message ?? '').contains(kOpen),
  );

  testWidgets('note Mistral : puce « ≈ 0,01 \$ », localisée', (
    WidgetTester tester,
  ) async {
    // 1 min 30 s de temps réel = 0,012 $.
    await pump(tester, session(realtimeMs: 90000));

    final Finder chip = find.textContaining(RegExp(r'≈\s?0,01\s?\$'));
    expect(chip, findsOneWidget);
    expect(tester.widget<Text>(chip).data, contains(kOpen));
  });

  testWidgets('temps réel et rattrapage s additionnent : « ≈ 1,51 \$ »', (
    WidgetTester tester,
  ) async {
    // 3 h de réunion (1,44 $) + 20 min de rattrapage (0,07 $).
    await pump(tester, session(realtimeMs: 10800000, batchMs: 1200000));

    expect(find.textContaining(RegExp(r'≈\s?1,51\s?\$')), findsOneWidget);
  });

  testWidgets('moins d un centime : « < 0,01 \$ »', (
    WidgetTester tester,
  ) async {
    // 1 min de temps réel = 0,008 $.
    await pump(tester, session(realtimeMs: 60000));

    final Finder chip = find.textContaining(RegExp(r'<\s?0,01\s?\$'));
    expect(chip, findsOneWidget);
    expect(tester.widget<Text>(chip).data, contains(kOpen));
    expect(find.textContaining(RegExp(r'≈\s?0,0')), findsNothing);
  });

  testWidgets('rattrapage seul (note locale rattrapée en ligne) : la puce '
      'aussi', (WidgetTester tester) async {
    // 12 min de batch = 0,042 $ → « ≈ 0,04 $ ».
    await pump(tester, session(batchMs: 720000));

    expect(find.textContaining(RegExp(r'≈\s?0,04\s?\$')), findsOneWidget);
  });

  testWidgets('infobulle : transcription Mistral seule, résumé non compris', (
    WidgetTester tester,
  ) async {
    await pump(tester, session(realtimeMs: 90000));

    expect(tooltip(), findsOneWidget);
    final String message = tester.widget<Tooltip>(tooltip()).message!;
    expect(message.toLowerCase(), contains('résumé'));
  });

  testWidgets('note locale (rien envoyé) : ni puce ni infobulle', (
    WidgetTester tester,
  ) async {
    await pump(tester, session());

    expect(find.text('Point équipe'), findsWidgets, reason: 'fiche chargée');
    expect(find.textContaining(anyPrice), findsNothing);
    expect(tooltip(), findsNothing);
  });
}
