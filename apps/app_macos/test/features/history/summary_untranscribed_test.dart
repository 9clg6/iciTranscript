import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';

import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Tour 7, point 4 : un passage non transcrit n'entre pas dans le texte
/// envoyé au résumé comme s'il avait été dit (il n'est la phrase de
/// personne) ; l'entrée peut signaler qu'un passage manque.
void main() {
  test('le repère n est pas envoyé au résumé comme une phrase dite', () async {
    resetPrefs();
    final AppDatabase db = memoryDatabase();
    final ScriptedLlmProvider llm = ScriptedLlmProvider(
      (LlmChatRequest r, int i) => Stream<String>.value('Résumé.'),
    );
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
    final String marker = LiveTranscriptionService.untranscribedMarkerText(
      10000,
      15000,
    );
    await seedNote(c, <TranscriptSegmentEntity>[
      noteSegment(0, 'We need the budget by Friday.'),
      noteSegment(2, marker),
      noteSegment(4, 'I agree, Friday works.', source: AudioSource.input),
    ]);
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);

    await c.read(note.notifier).generateSummary();

    final String sent = llm.requests.map(requestText).join('\n');
    expect(sent, contains('We need the budget by Friday.'));
    expect(sent, contains('I agree, Friday works.'));
    expect(
      sent,
      isNot(contains(': $marker')),
      reason: 'pas une ligne « [hh:mm:ss] SOURCE: … » avec le repère',
    );
  });
}
