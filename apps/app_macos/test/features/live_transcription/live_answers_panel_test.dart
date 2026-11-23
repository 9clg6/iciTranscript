import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/fake_view_models.dart' show settle;
import '../../helpers/live_answers_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/text_weight.dart';

/// Zone « Questions » de l'écran en direct (T4, besoin 11) : comportement,
/// pas pixels. Vrai `LiveAnswersService` monté sur les faux (LLM piloté par
/// le test), view model du direct figé.
///
/// API supposée :
/// - lib/core/providers/services/live_answers.service.provider.dart :
///   `liveAnswersServiceProvider` (keepAlive) → `LiveAnswersService` ; l'écran
///   affiche `questionsStream` et appelle `retry`, `dismiss`, `answerSegment`,
///   `answerLatestFromOthers`.
/// - Actions trouvées par leur libellé (texte visible ou info-bulle) :
///   `live_answers.copy`, `common.action.retry` (échec, aucun modèle),
///   `live_answers.answer` (question jamais lancée), `live_answers.dismiss`,
///   `live_answers.answer_latest`, et `live_answers.answer_this` sur chaque
///   ligne de transcription.
/// - Heure d'une question : décalage depuis le début, « HH:MM:SS » comme les
///   lignes de transcription ; interlocuteur : mêmes libellés qu'elles.
class _RecordingViewModel extends LiveTranscriptionViewModel {
  _RecordingViewModel(this.segments);

  final List<TranscriptSegmentEntity> segments;

  @override
  LiveTranscriptionState build() =>
      LiveTranscriptionState(segments: segments, isRecording: true);

  @override
  Future<void> recheckPermissions() async {}
}

void main() {
  const String q = 'Est-ce que vous avez prévu une date de livraison ?';
  const DocumentExcerpt contract = DocumentExcerpt(
    documentId: 'doc-contract',
    documentTitle: 'Contrat Acme 2026',
    text: 'Livraison du lot 1 le 12 mars 2026.',
  );

  late LiveAnswersHarness h;

  Future<void> pumpLive(
    WidgetTester tester, {
    List<TranscriptSegmentEntity> segments = const <TranscriptSegmentEntity>[],
    bool modelReady = true,
    bool isLocal = false,
  }) async {
    h = LiveAnswersHarness(modelReady: modelReady, isLocal: isLocal);
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      size: const Size(1440, 900),
      settle: false,
      overrides: <Override>[
        liveTranscriptionViewModelProvider.overrideWith(
          () => _RecordingViewModel(segments),
        ),
        liveAnswersServiceProvider.overrideWithValue(h.service),
      ],
    );
  }

  /// Une action, qu'elle soit un bouton texte ou une icône à info-bulle.
  Finder action(String key) {
    final String label = key.tr();
    final Finder tip = find.byTooltip(label);
    return tip.evaluate().isNotEmpty ? tip : find.text(label);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await settle(tester);
  }

  /// Un autre participant (interlocuteur 2) pose [text] à 1 min 05.
  Future<void> ask(WidgetTester tester, [String text = q]) async {
    h.hear(text, atMs: 65000, speaker: 1);
    await settle(tester);
  }

  testWidgets('avant toute question : la zone et son état vide', (
    WidgetTester tester,
  ) async {
    await pumpLive(tester);
    await settle(tester);

    expect(find.text('live_answers.title'.tr()), findsOneWidget);
    expect(find.text('live_answers.empty'.tr()), findsOneWidget);
  });

  testWidgets('une question détectée : son texte, qui l\'a posée et quand', (
    WidgetTester tester,
  ) async {
    await pumpLive(tester);
    await ask(tester);

    expect(find.text(q), findsOneWidget);
    expect(
      find.textContaining(
        'transcription.live.speaker_n'.tr(args: <String>['2']),
      ),
      findsWidgets,
    );
    expect(find.textContaining('00:01:05'), findsWidgets);
    expect(find.text('live_answers.empty'.tr()), findsNothing);
  });

  testWidgets('la réponse s\'affiche dès le premier morceau, puis grandit', (
    WidgetTester tester,
  ) async {
    await pumpLive(tester);
    await ask(tester);

    h.llm.last.delta('La livraison');
    await settle(tester);
    expect(find.textContaining('La livraison'), findsOneWidget);

    h.llm.last.delta(' est prévue le 12 mars.');
    await settle(tester);
    expect(
      find.textContaining('La livraison est prévue le 12 mars.'),
      findsOneWidget,
    );
  });

  testWidgets('sources : le titre du document cité, jamais une source '
      'inventée', (WidgetTester tester) async {
    await pumpLive(tester);
    h.search.results = <DocumentExcerpt>[contract];
    await ask(tester);

    h.llm.last.reply('Le lot 1 arrive le 12 mars [S1], le lot 2 en mai [S2].');
    await settle(tester);

    expect(find.textContaining('Contrat Acme 2026'), findsOneWidget);
    expect(find.textContaining('[S2]'), findsNothing);
  });

  testWidgets('« Copier la réponse » met la réponse au presse-papiers', (
    WidgetTester tester,
  ) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.reply('Le lot 1 arrive le 12 mars.');
    await settle(tester);

    await tap(tester, action('live_answers.copy'));

    expect(copied, hasLength(1));
    expect(copied.single, contains('Le lot 1 arrive le 12 mars.'));
  });

  final Map<Object, String> failures = <Object, String>{
    const LlmInvalidKeyException('anthropic'): 'live_answers.error.invalid_key',
    const LlmRateLimitedException('openai'): 'live_answers.error.rate_limited',
    const LlmUnreachableException('gemini'): 'live_answers.error.unreachable',
    const LlmException('autre'): 'live_answers.error.other',
    const FormatException('ligne JSON invalide'):
        'live_answers.error.malformed',
  };
  failures.forEach((Object error, String key) {
    testWidgets('${error.runtimeType} : message « $key » et « Réessayer »', (
      WidgetTester tester,
    ) async {
      await pumpLive(tester);
      await ask(tester);
      h.llm.last.fail(error);
      await settle(tester);

      expect(find.text(key.tr()), findsOneWidget);
      expect(action('common.action.retry'), findsWidgets);
    });
  });

  testWidgets('« Réessayer » relance la question et montre la nouvelle '
      'réponse', (WidgetTester tester) async {
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.fail(const LlmUnreachableException('anthropic'));
    await settle(tester);

    await tap(tester, action('common.action.retry'));
    expect(h.llm.requests, hasLength(2));
    h.llm.last.reply('Le 12 mars.');
    await settle(tester);

    expect(find.textContaining('Le 12 mars.'), findsOneWidget);
    expect(find.text('live_answers.error.unreachable'.tr()), findsNothing);
  });

  testWidgets('entre la détection et le premier morceau : « Réponse en '
      'cours… »', (WidgetTester tester) async {
    await pumpLive(tester);
    await ask(tester);

    expect(find.text('live_answers.answering'.tr()), findsOneWidget);
  });

  testWidgets('une question restée en attente (une plus récente est passée '
      'avant) se lance à la main', (WidgetTester tester) async {
    const String b = 'Combien coûte la licence par utilisateur ?';
    const String c = 'Où sont hébergés les serveurs ?';
    await pumpLive(tester);
    await ask(tester);
    h
      ..hear(b, atMs: 66000)
      ..hear(c, atMs: 67000);
    await settle(tester);
    h.llm.last.reply('Le 12 mars.');
    await settle(tester);
    h.llm.last.reply('En France.');
    await settle(tester);
    expect(h.llm.requests, hasLength(2));

    await tap(tester, action('live_answers.answer'));

    expect(h.llm.requests, hasLength(3));
    expect(h.llm.last.request.messages.last.content, contains(b));
  });

  testWidgets('« Ignorer » retire la question', (WidgetTester tester) async {
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.reply('Le 12 mars.');
    await settle(tester);

    await tap(tester, action('live_answers.dismiss'));

    expect(find.text(q), findsNothing);
    expect(h.questions, isEmpty);
  });

  testWidgets('refus du modèle : la question reste, sans réponse, avec la '
      'mention dédiée', (WidgetTester tester) async {
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.reply('NO_ANSWER');
    await settle(tester);

    expect(find.text(q), findsOneWidget);
    expect(find.text('live_answers.declined'.tr()), findsOneWidget);
    expect(find.textContaining('NO_ANSWER'), findsNothing);
  });

  testWidgets('réponse coupée : montrée, marquée incomplète', (
    WidgetTester tester,
  ) async {
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.reply('La livraison est prévue pour le lot 1 au début du');
    await settle(tester);

    expect(find.textContaining('au début du'), findsOneWidget);
    expect(find.text('live_answers.truncated'.tr()), findsOneWidget);
  });

  testWidgets('aucun modèle prêt : la question est listée avec l\'invite à '
      'configurer un modèle', (WidgetTester tester) async {
    await pumpLive(tester, modelReady: false);
    await ask(tester);

    expect(find.text(q), findsOneWidget);
    expect(find.textContaining('llm.configure_model'.tr()), findsOneWidget);
    expect(h.llm.requests, isEmpty);
    expect(action('common.action.retry'), findsWidgets);
  });

  testWidgets('« Répondre » répond à la dernière phrase des autres même si '
      'ce n\'était pas une question', (WidgetTester tester) async {
    await pumpLive(tester);
    h.hear('On aimerait une livraison en mars.', atMs: 60000);
    await settle(tester);
    expect(h.questions, isEmpty);

    await tap(tester, action('live_answers.answer_latest'));

    expect(h.questions.single.text, 'On aimerait une livraison en mars.');
    expect(h.llm.requests, hasLength(1));
    expect(find.text('On aimerait une livraison en mars.'), findsWidgets);
  });

  testWidgets('« Répondre à cette phrase » sur sa propre ligne : la phrase '
      'devient une question', (WidgetTester tester) async {
    final TranscriptSegmentEntity mine = TranscriptSegmentEntity(
      id: 'seg-mine',
      sessionId: 's1',
      source: AudioSource.input,
      text: 'Je me demande si on peut livrer en mars.',
      timestampMs: 30000,
      createdAt: DateTime(2026, 11, 22, 10),
    );
    await pumpLive(tester, segments: <TranscriptSegmentEntity>[mine]);
    await settle(tester);

    await tap(tester, action('live_answers.answer_this'));

    expect(h.questions.single.text, mine.text);
    expect(h.questions.single.source, AudioSource.input);
    expect(h.llm.requests, hasLength(1));
    expect(h.questions.single.status, LiveQuestionStatus.answering);
  });

  testWidgets('modèle local : la question est listée, l\'écran dit que la '
      'réponse se demande, et « Proposer une réponse » la lance', (
    WidgetTester tester,
  ) async {
    await pumpLive(tester, isLocal: true);
    await ask(tester);

    expect(find.text(q), findsOneWidget);
    expect(
      find.textContaining('live_answers.local_manual_hint'.tr()),
      findsOneWidget,
    );
    expect(h.llm.requests, isEmpty);

    await tap(tester, action('live_answers.answer'));

    expect(h.llm.requests, hasLength(1));
  });

  testWidgets('la phrase de tête est en gras (semi-gras ou plus), les puces '
      'en texte normal', (WidgetTester tester) async {
    await pumpLive(tester);
    await ask(tester);
    h.llm.last.reply(
      'Le lot 1 arrive le 12 mars.\n- Recette en avril.\n- Formation incluse.',
    );
    await settle(tester);

    expect(
      FontWeight.values.indexOf(
        weightOf(tester, 'Le lot 1 arrive le 12 mars.'),
      ),
      greaterThanOrEqualTo(FontWeight.values.indexOf(FontWeight.w600)),
    );
    expect(
      FontWeight.values.indexOf(weightOf(tester, 'Recette en avril.')),
      lessThan(FontWeight.values.indexOf(FontWeight.w600)),
    );
    expect(
      FontWeight.values.indexOf(weightOf(tester, 'Formation incluse.')),
      lessThan(FontWeight.values.indexOf(FontWeight.w600)),
    );
  });
}
