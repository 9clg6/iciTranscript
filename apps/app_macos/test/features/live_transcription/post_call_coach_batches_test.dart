import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/llm_fakes.dart'
    show noteSegment, seedNote, storedAnalysis, streamOf, writeLlmPrefs;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// Transport factice dont la réponse dépend du rang de la requête (0, 1…).
class _ByIndexHttp extends RecordingHttpAdapter {
  _ByIndexHttp(this.replyFor);

  final FakeReply Function(int index) replyFor;

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

/// Coach en direct qui a déjà trouvé [found] sur les phrases [coached].
class _FoundLive extends LiveCoachService {
  _FoundLive(this.found, this.coached) : super(resolveModel: () async => null);

  final List<EnglishCorrectionEntity> found;
  final Set<String> coached;

  @override
  LiveCoachSnapshot get snapshot => LiveCoachSnapshot(corrections: found);

  @override
  Set<String> get coachedSegmentIds => coached;
}

/// Coach de fin d'appel (interrupteur « Coach anglais » activé), par le vrai
/// view model du direct ; modèle local installé, transport factice.
///
/// Besoin : à la fin d'une note, le retour est produit sur la seule parole
/// anglaise de l'utilisateur, par lots bornés (règles détaillées dans
/// test/application/services/llm/coach_meeting_test.dart), et la NOTE garde
/// le résultat, quel qu'il soit :
/// - aucune correction : un retour vide est rangé (la note dira « Aucune
///   correction », pas le silence d'aujourd'hui) ;
/// - une partie échoue : corrections gardées + phrases non analysées rangées
///   (la note propose de réessayer) ;
/// - tout échoue : la note le dit quand même (toutes les phrases anglaises
///   de l'utilisateur rangées non analysées) ; aujourd'hui l'échec reste
///   dans l'état du direct et n'atteint jamais la note ;
/// - ce que le coach en direct a trouvé est rangé avec, et ses phrases ne
///   repartent pas (pas de doublon, pas de travail refait).
///
/// API supposée : `coachAfterCall(segments, {sessionId})`, segments =
/// `List<TranscriptSegmentEntity>` (remplace la version qui prenait un texte : elle ne
/// voyait ni source, ni heure, ni repère) ; lit `liveCoachServiceProvider`
/// (`snapshot.corrections`, `coachedSegmentIds`).
void main() {
  late AppDatabase db;
  late RecordingHttpAdapter http;

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

  Future<ProviderContainer> launch({
    required List<TranscriptSegmentEntity> segments,
    required FakeReply Function(int index) replyFor,
    LiveCoachService? live,
  }) async {
    await writeLlmPrefs(cloudAllowed: false);
    db = memoryDatabase();
    http = _ByIndexHttp(replyFor);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = http),
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
        if (live != null) liveCoachServiceProvider.overrideWithValue(live),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, segments);
    return c;
  }

  Future<void> coach(ProviderContainer c, List<TranscriptSegmentEntity> s) => c
      .read(liveTranscriptionViewModelProvider.notifier)
      .coachAfterCall(s, sessionId: 's1');

  String sentAt(int i) => jsonEncode(http.bodies[i]);
  String allSent() => http.bodies.map(jsonEncode).join('\n');

  /// 60 minutes : une phrase anglaise de l'utilisateur toutes les 5 s.
  final List<TranscriptSegmentEntity> hour = <TranscriptSegmentEntity>[
    for (int i = 0; i < 720; i++)
      noteSegment(
        i,
        'Line $i: we need to check the figures for the next release.',
        source: AudioSource.input,
      ),
  ];

  test('seule la parole anglaise du micro part : ni l\'interlocuteur, ni un '
      'repère, ni une phrase en français', () async {
    final List<TranscriptSegmentEntity> meeting = <TranscriptSegmentEntity>[
      noteSegment(
        0,
        'I am agree with you on this point.',
        source: AudioSource.input,
      ),
      noteSegment(1, 'We need the budget by Friday.'),
      noteSegment(
        2,
        LiveTranscriptionService.untranscribedMarkerText(10000, 14000),
        source: AudioSource.input,
      ),
      noteSegment(
        3,
        'Je pense que le budget est validé pour la semaine.',
        source: AudioSource.input,
      ),
    ];
    final ProviderContainer c = await launch(
      segments: meeting,
      replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
    );

    await coach(c, meeting);

    expect(allSent(), contains('I am agree with you on this point.'));
    expect(allSent(), isNot(contains('budget by Friday')));
    expect(allSent(), isNot(contains('Passage non transcrit')));
    expect(allSent(), isNot(contains('le budget est valid')));
  });

  test('aucune correction : un retour vide est rangé avec la note', () async {
    final List<TranscriptSegmentEntity> meeting = <TranscriptSegmentEntity>[
      noteSegment(
        0,
        'I agree with you on this point.',
        source: AudioSource.input,
      ),
    ];
    final ProviderContainer c = await launch(
      segments: meeting,
      replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
    );

    await coach(c, meeting);

    final EnglishFeedbackEntity? saved = (await storedAnalysis(db)).feedback;
    expect(saved, isNotNull, reason: 'la note doit dire « Aucune correction »');
    expect(saved!.corrections, isEmpty);
    expect(saved.unanalyzedSegmentIds, isEmpty);
  });

  test('60 minutes, une partie échoue : corrections des autres parties et '
      'phrases non analysées rangées', () async {
    final ProviderContainer c = await launch(
      segments: hour,
      replyFor: (int i) => i == 1
          ? const UnreachableReply()
          : ok(feedbackJson(<(String, String)>[('phrase $i', 'corrigée $i')])),
    );

    await coach(c, hour);

    expect(http.requests.length, greaterThan(2));
    final EnglishFeedbackEntity saved = (await storedAnalysis(db)).feedback!;
    expect(saved.corrections, hasLength(http.requests.length - 1));
    final Set<String> inFailed = <String>{
      for (final TranscriptSegmentEntity s in hour)
        if (sentAt(1).contains(s.text)) s.id,
    };
    expect(inFailed, isNotEmpty);
    expect(saved.unanalyzedSegmentIds.toSet(), inFailed);
  });

  test('tout échoue : la note le dit quand même (toutes les phrases '
      'anglaises de l\'utilisateur non analysées)', () async {
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
    ];
    final ProviderContainer c = await launch(
      segments: meeting,
      replyFor: (_) => const UnreachableReply(),
    );

    await coach(c, meeting);

    final EnglishFeedbackEntity? saved = (await storedAnalysis(db)).feedback;
    expect(saved, isNotNull, reason: 'l\'échec doit atteindre la note');
    expect(saved!.corrections, isEmpty);
    expect(saved.unanalyzedSegmentIds.toSet(), <String>{'seg-0', 'seg-2'});
  });

  group('après le coach en direct', () {
    const EnglishCorrectionEntity foundLive = EnglishCorrectionEntity(
      original: 'I am agree',
      corrected: 'I agree',
      category: 'grammar',
      explanation: '« agree » est un verbe.',
      timestampMs: 0,
    );
    final List<TranscriptSegmentEntity> meeting = <TranscriptSegmentEntity>[
      noteSegment(
        0,
        'I am agree with you on this point.',
        source: AudioSource.input,
      ),
      noteSegment(
        1,
        'He have sent the deck to the client.',
        source: AudioSource.input,
      ),
    ];

    test('les phrases corrigées en direct ne repartent pas ; la note garde '
        'les deux retours, sans doublon', () async {
      final ProviderContainer c = await launch(
        segments: meeting,
        live: _FoundLive(
          const <EnglishCorrectionEntity>[foundLive],
          <String>{'seg-0'},
        ),
        // Un modèle qui redit la correction du direct ne la double pas.
        replyFor: (_) => ok(
          feedbackJson(<(String, String)>[
            ('He have sent', 'He has sent'),
            ('I am agree', 'I agree'),
          ]),
        ),
      );

      await coach(c, meeting);

      expect(allSent(), isNot(contains('I am agree with you')));
      expect(allSent(), contains('He have sent the deck'));
      final List<String> saved = (await storedAnalysis(db))
          .feedback!
          .corrections
          .map((EnglishCorrectionEntity x) => x.corrected)
          .toList();
      expect(saved, unorderedEquals(<String>['I agree', 'He has sent']));
    });

    test('tout corrigé en direct : aucune requête, la note garde le retour '
        'du direct', () async {
      final ProviderContainer c = await launch(
        segments: meeting,
        live: _FoundLive(
          const <EnglishCorrectionEntity>[foundLive],
          <String>{'seg-0', 'seg-1'},
        ),
        replyFor: (_) => ok(feedbackJson(<(String, String)>[])),
      );

      await coach(c, meeting);

      expect(http.requests, isEmpty);
      expect(
        (await storedAnalysis(db)).feedback?.corrections.single.corrected,
        'I agree',
      );
    });
  });
}
