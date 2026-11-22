import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';

import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Résumé d'une longue réunion (besoin B8) : aujourd'hui le transcript est
/// coupé en silence à 8000 caractères (les DERNIERS, `_truncate` dans
/// ollama.service.dart) ; le début d'une réunion d'une heure n'est jamais lu.
///
/// Attendu, quelle que soit la stratégie (map-reduce, fenêtre glissante) :
/// - une réunion courte = une seule requête qui contient tout ;
/// - une réunion de 60 min = plusieurs requêtes bornées, chaque passage du
///   transcript dans au moins une, et une synthèse finale qui reprend les
///   réponses intermédiaires ; le résumé affiché et rangé = la synthèse.
///
/// Borne supposée : au plus [maxRequestChars] caractères de consignes et de
/// messages par requête (le modèle local tourne avec num_ctx 4096).
const int maxRequestChars = 10000;

void main() {
  late AppDatabase db;
  late ScriptedLlmProvider llm;

  /// Chaque réponse intermédiaire est unique et finit par un point.
  String replyFor(int i) => 'Partie $i : décision $i validée.';

  Future<(ProviderContainer, SessionDetailViewModelProvider)> openNote(
    List<TranscriptSegmentEntity> segments,
  ) async {
    resetPrefs();
    db = memoryDatabase();
    llm = ScriptedLlmProvider(
      (LlmChatRequest r, int i) => Stream<String>.value(replyFor(i)),
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
    await seedNote(c, segments);
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);
    return (c, note);
  }

  /// Réunion de 60 min : une intervention toutes les 5 s, chacune marquée
  /// d'un repère unique « Intervention NNNN ».
  final List<TranscriptSegmentEntity> hour = <TranscriptSegmentEntity>[
    for (int i = 0; i < 720; i++)
      noteSegment(
        i,
        'Intervention ${i.toString().padLeft(4, '0')} : nous avançons sur '
        'le sujet $i et ses conséquences pour l\'équipe.',
        source: i.isEven ? AudioSource.input : AudioSource.output,
      ),
  ];

  test('réunion courte : une seule requête, qui contient tout le transcript',
      () async {
    final (ProviderContainer c, SessionDetailViewModelProvider note) =
        await openNote(kShortMeeting);

    await c.read(note.notifier).generateSummary();

    expect(llm.requests, hasLength(1));
    final String sent = requestText(llm.requests.single);
    expect(sent, contains('I am agree with you.'));
    expect(sent, contains('We need the budget by Friday.'));
    expect(c.read(note).value!.summary, replyFor(0));
  });

  group('réunion de 60 minutes', () {
    test('chaque passage du transcript part dans au moins une requête, dont '
        'le début', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(hour);

      await c.read(note.notifier).generateSummary();

      expect(llm.requests.length, greaterThan(1));
      final List<String> sent = llm.requests.map(requestText).toList();
      final List<String> missing = <String>[
        for (int i = 0; i < hour.length; i++)
          if (!sent.any(
            (String s) =>
                s.contains('Intervention ${i.toString().padLeft(4, '0')}'),
          ))
            'Intervention ${i.toString().padLeft(4, '0')}',
      ];
      expect(missing, isEmpty, reason: 'passages jamais envoyés au modèle');
    });

    test('aucune requête ne dépasse la borne', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(hour);

      await c.read(note.notifier).generateSummary();

      for (final LlmChatRequest r in llm.requests) {
        expect(requestText(r).length, lessThanOrEqualTo(maxRequestChars));
      }
    });

    test('synthèse finale : chaque réponse intermédiaire est reprise par une '
        'requête suivante ; le résumé affiché et rangé est la synthèse',
        () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(hour);

      await c.read(note.notifier).generateSummary();

      final int last = llm.requests.length - 1;
      for (int i = 0; i < last; i++) {
        expect(
          llm.requests
              .skip(i + 1)
              .map(requestText)
              .any((String s) => s.contains(replyFor(i))),
          isTrue,
          reason: 'réponse $i jamais reprise',
        );
      }
      expect(c.read(note).value!.summary, replyFor(last));
      expect((await storedAnalysis(db)).summary, replyFor(last));
    });
  });
}
