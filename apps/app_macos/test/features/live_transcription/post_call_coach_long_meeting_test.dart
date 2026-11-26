import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/coach_fakes.dart';
import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Seul build() est remplacé (pas de serveur, micro ni permissions) ;
/// le coach de fin d'appel testé est le vrai code du view model.
class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// Coach à la fin d'une longue réunion (bug du 2026-11-26 : 78 min,
/// « Réponse du modèle illisible », 90/116 phrases non analysées).
///
/// Besoin : avec un fournisseur qui coupe sa réponse à 4 096 jetons comme
/// le vrai ([tokenLimitedCoach]), le retour rangé dans la note couvre
/// chaque phrase de l'utilisateur, aucune n'est notée non analysée.
void main() {
  test('~9 k caractères au micro : le retour rangé a une correction par '
      'phrase, aucune phrase non analysée', () async {
    resetPrefs();
    final AppDatabase db = memoryDatabase();
    final List<TranscriptSegmentEntity> meeting = denseMicMeeting(90);
    final ScriptedLlmProvider llm = tokenLimitedCoach(<String>[
      for (final TranscriptSegmentEntity s in meeting) s.text,
    ]);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = RecordingHttpAdapter(),
        ),
        activeLlmProviderProvider.overrideWith((Ref ref) async => llm),
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final DateTime start = DateTime(2026, 11, 26, 10, 38);
    await c
        .read(sessionRepositoryProvider)
        .create(
          SessionEntity(
            id: 's1',
            title: 'Weekly sync',
            createdAt: start,
            updatedAt: start,
            durationSeconds: 78 * 60,
            status: SessionStatus.completed,
          ),
        );

    await c
        .read(liveTranscriptionViewModelProvider.notifier)
        .coachAfterCall(meeting, sessionId: 's1');

    final EnglishFeedbackEntity? stored = SessionAnalysis.fromStored(
      await c.read(summaryServiceProvider).getSummaryForSession('s1'),
    ).feedback;
    expect(llm.requests, isNotEmpty);
    expect(
      stored?.unanalyzedSegmentIds,
      isEmpty,
      reason:
          '${stored?.unanalyzedSegmentIds.length}/${meeting.length} phrases '
          'non analysées',
    );
    expect(
      stored?.corrections
          .map((EnglishCorrectionEntity x) => x.original)
          .toSet(),
      <String>{
        for (final TranscriptSegmentEntity s in meeting)
          coachOriginalOf(s.text),
      },
    );
  });
}
