import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';

import '../../helpers/coach_fakes.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// « Réessayer » sur une note dont le coach a échoué en partie (bug du
/// 2026-11-26 : note de 78 min, 90/116 phrases non analysées, « Réponse du
/// modèle illisible » à chaque essai).
///
/// Besoin : Réessayer renvoie seulement les phrases non analysées ; avec un
/// fournisseur qui coupe sa réponse à 4 096 jetons comme le vrai
/// ([tokenLimitedCoach]), la note est réparée : plus d'erreur, plus de
/// phrase non analysée, les nouvelles corrections s'ajoutent aux anciennes.
///
/// Monde : vrai view model de la note, vrais dépôts sur base en mémoire,
/// fournisseur actif remplacé par le factice (aucun réseau).
void main() {
  late AppDatabase db;
  late ScriptedLlmProvider llm;

  EnglishCorrectionEntity correctionOf(String sentence) =>
      EnglishCorrectionEntity(
        original: coachOriginalOf(sentence),
        corrected: '${coachOriginalOf(sentence)}, corrected',
        category: 'grammar',
        explanation: 'Accord du verbe.',
      );

  /// Note `s1` de [meeting], avec un retour du coach déjà rangé : une
  /// correction pour chaque phrase de [analyzed], [unanalyzed] notées non
  /// analysées. Rend le view model de la note, chargé.
  Future<(ProviderContainer, SessionDetailViewModelProvider)> openNote(
    List<TranscriptSegmentEntity> meeting, {
    required List<TranscriptSegmentEntity> analyzed,
    required List<TranscriptSegmentEntity> unanalyzed,
    required ScriptedLlmProvider provider,
  }) async {
    resetPrefs();
    db = memoryDatabase();
    llm = provider;
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = RecordingHttpAdapter(),
        ),
        activeLlmProviderProvider.overrideWith((Ref ref) async => llm),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, meeting);
    await c
        .read(summaryServiceProvider)
        .saveSummary(
          sessionId: 's1',
          content: SessionAnalysis(
            feedback: EnglishFeedbackEntity(
              overall: 'Niveau intermédiaire.',
              corrections: <EnglishCorrectionEntity>[
                for (final TranscriptSegmentEntity s in analyzed)
                  correctionOf(s.text),
              ],
              unanalyzedSegmentIds: <String>[
                for (final TranscriptSegmentEntity s in unanalyzed) s.id,
              ],
            ),
          ).toStored(),
        );
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);
    expect(
      c.read(note).value!.feedback?.unanalyzedSegmentIds,
      hasLength(unanalyzed.length),
      reason: 'prémisse : le retour rangé est chargé dans la note',
    );
    return (c, note);
  }

  test(
    'note de 116 phrases dont 90 non analysées (~9 k caractères) : '
    'Réessayer la répare, sans erreur, toutes les phrases corrigées',
    () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(116);
      final List<TranscriptSegmentEntity> analyzed = meeting.sublist(0, 26);
      final List<TranscriptSegmentEntity> unanalyzed = meeting.sublist(26);
      final (
        ProviderContainer c,
        SessionDetailViewModelProvider note,
      ) = await openNote(
        meeting,
        analyzed: analyzed,
        unanalyzed: unanalyzed,
        provider: tokenLimitedCoach(<String>[
          for (final TranscriptSegmentEntity s in meeting) s.text,
        ]),
      );

      await c.read(note.notifier).retryUnanalyzed();

      final SessionDetailState s = c.read(note).value!;
      expect(s.feedbackError, isNull, reason: 'erreur affichée sur la note');
      final Set<String> all = <String>{
        for (final TranscriptSegmentEntity x in meeting)
          coachOriginalOf(x.text),
      };
      for (final EnglishFeedbackEntity? f in <EnglishFeedbackEntity?>[
        s.feedback,
        (await storedAnalysis(db)).feedback,
      ]) {
        expect(f?.unanalyzedSegmentIds, isEmpty);
        expect(
          f?.corrections.map((EnglishCorrectionEntity x) => x.original).toSet(),
          all,
          reason: 'anciennes corrections gardées, une par phrase réessayée',
        );
      }
    },
  );

  test(
    'locuteur plus dense (chaque lot rend une réponse coupée) : Réessayer '
    'coupe les lots illisibles en deux et répare la note, sans erreur',
    () async {
      final List<TranscriptSegmentEntity> meeting = denseMicMeeting(116);
      final List<TranscriptSegmentEntity> analyzed = meeting.sublist(0, 26);
      final List<TranscriptSegmentEntity> unanalyzed = meeting.sublist(26);
      final (
        ProviderContainer c,
        SessionDetailViewModelProvider note,
      ) = await openNote(
        meeting,
        analyzed: analyzed,
        unanalyzed: unanalyzed,
        provider: tokenLimitedCoach(<String>[
          for (final TranscriptSegmentEntity s in meeting) s.text,
        ], answerCharsPerChar: kDenserSpeakerAnswerCharsPerChar),
      );

      await c.read(note.notifier).retryUnanalyzed();

      final SessionDetailState s = c.read(note).value!;
      expect(s.feedbackError, isNull, reason: 'erreur affichée sur la note');
      expect(
        s.feedback?.unanalyzedSegmentIds,
        isEmpty,
        reason:
            '${s.feedback?.unanalyzedSegmentIds.length}/${unanalyzed.length} '
            'phrases non analysées',
      );
      expect(
        s.feedback?.corrections
            .map((EnglishCorrectionEntity x) => x.original)
            .toSet(),
        <String>{
          for (final TranscriptSegmentEntity x in meeting)
            coachOriginalOf(x.text),
        },
      );
      expect(llm.requests.length, lessThanOrEqualTo(2 * unanalyzed.length));
    },
  );

  test('Réessayer ne renvoie que les phrases non analysées', () async {
    final List<TranscriptSegmentEntity> meeting = denseMicMeeting(6);
    final List<TranscriptSegmentEntity> analyzed = <TranscriptSegmentEntity>[
      meeting[0],
      meeting[2],
      meeting[4],
    ];
    final List<TranscriptSegmentEntity> unanalyzed = <TranscriptSegmentEntity>[
      meeting[1],
      meeting[3],
      meeting[5],
    ];
    final (
      ProviderContainer c,
      SessionDetailViewModelProvider note,
    ) = await openNote(
      meeting,
      analyzed: analyzed,
      unanalyzed: unanalyzed,
      provider: tokenLimitedCoach(<String>[
        for (final TranscriptSegmentEntity s in meeting) s.text,
      ]),
    );

    await c.read(note.notifier).retryUnanalyzed();

    final String sent = llm.requests.map(requestText).join('\n');
    for (final TranscriptSegmentEntity s in unanalyzed) {
      expect(sent, contains(s.text));
    }
    for (final TranscriptSegmentEntity s in analyzed) {
      expect(sent, isNot(contains(s.text)), reason: 'déjà analysée');
    }
    expect(c.read(note).value!.feedback?.unanalyzedSegmentIds, isEmpty);
  });
}
