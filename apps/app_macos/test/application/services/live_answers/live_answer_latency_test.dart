import 'dart:convert';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';

import '../../../helpers/live_answers_fakes.dart';
import '../../../helpers/settings_fakes.dart';

/// Latence des réponses en direct avec Claude. Documentation Anthropic,
/// « Reduce latency » (consultée par le coordinateur, 2026-11-23,
/// https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-latency) :
/// l'effort est le premier levier de vitesse ; exemple à `low` avec
/// `"output_config": {"effort": "low"}` et `max_tokens` 1024.
///
/// Attendu, sur le corps JSON réellement posté :
/// - une requête de RÉPONSE EN DIRECT (construite par `LiveAnswersService`)
///   envoyée par le fournisseur Anthropic porte `output_config: {effort:
///   low}` et `max_tokens` 1024 ;
/// - un résumé ou un retour du coach par le même fournisseur : inchangés
///   (aucun `output_config`, `max_tokens` = `kLlmAnswerMaxTokens`) ;
/// - la propriété « priorité à la latence » est portée par la requête
///   (nom au choix de l'implémenteur) : OpenAI, Gemini et Ollama l'ignorent
///   sans erreur, leur corps est celui de la même requête sans elle.
void main() {
  const String claudeKey = 'sk-ant-test-SECRET-0123456789';
  const String question = 'Est-ce que vous avez prévu une date de livraison ?';

  LlmProvider provider(LlmProviderId id, RecordingHttpAdapter http) =>
      buildLlmProvider(
        id,
        dio: Dio()..httpClientAdapter = http,
        apiKey: claudeKey,
        model: 'model-under-test',
      );

  /// Requête réellement construite par le service pour [question].
  Future<LlmChatRequest> liveRequestVia(ScriptedLlmProvider llm) async {
    final LiveAnswersService service = LiveAnswersService(
      resolveModel: () async =>
          LiveAnswerModel(provider: llm, modelId: 'model-under-test'),
      searchDocuments: FakeDocumentSearch().call,
      store: InMemoryQuestionStore(),
    )..start('s1');
    addTearDown(service.stop);
    service.onSegmentFinalized(
      TranscriptSegmentEntity(
        id: 'seg-1',
        sessionId: 's1',
        source: AudioSource.output,
        text: question,
        timestampMs: 65000,
        createdAt: DateTime(2026, 11, 23, 10),
      ),
      speaker: 0,
    );
    await eventually(() => expect(llm.requests, hasLength(1)));
    return llm.requests.single;
  }

  /// Corps posté par le fournisseur Anthropic pour la réponse en direct,
  /// passée par le vrai service.
  Future<Map<String, dynamic>> liveBodyViaService() async {
    final RecordingHttpAdapter http = RecordingHttpAdapter(
      reply: BodyReply(200, kOkStream[LlmProviderId.anthropic]!),
    );
    final LiveAnswersService service = LiveAnswersService(
      resolveModel: () async => LiveAnswerModel(
        provider: provider(LlmProviderId.anthropic, http),
        modelId: 'model-under-test',
      ),
      searchDocuments: FakeDocumentSearch().call,
      store: InMemoryQuestionStore(),
    )..start('s1');
    addTearDown(service.stop);
    service.onSegmentFinalized(
      TranscriptSegmentEntity(
        id: 'seg-1',
        sessionId: 's1',
        source: AudioSource.output,
        text: question,
        timestampMs: 65000,
        createdAt: DateTime(2026, 11, 23, 10),
      ),
      speaker: 0,
    );
    await eventually(() => expect(http.bodies, hasLength(1)));
    return http.bodies.single!;
  }

  /// La même requête, reconstruite avec les seuls champs d'aujourd'hui.
  LlmChatRequest plainCopy(LlmChatRequest r) => LlmChatRequest(
    systemPrompt: r.systemPrompt,
    messages: r.messages,
    maxTokens: r.maxTokens,
    model: r.model,
  );

  Future<Map<String, dynamic>> bodyOf(
    LlmProviderId id,
    LlmChatRequest request,
  ) async {
    final RecordingHttpAdapter http = RecordingHttpAdapter(
      reply: BodyReply(200, kOkStream[id]!),
    );
    await provider(id, http).streamChat(request).drain<void>();
    return http.bodies.single!;
  }

  group('Anthropic', () {
    test(
      'réponse en direct (vrai service) : effort low et max_tokens 1024',
      () async {
        final Map<String, dynamic> body = await liveBodyViaService();

        expect(body['output_config'], <String, Object?>{'effort': 'low'});
        expect(body['max_tokens'], 1024);
      },
    );

    test('résumé : inchangé (pas d\'effort, max_tokens habituel)', () async {
      final RecordingHttpAdapter http = RecordingHttpAdapter(
        reply: BodyReply(200, kOkStream[LlmProviderId.anthropic]!),
      );
      await summarizeMeeting(
        provider(LlmProviderId.anthropic, http),
        'Bonjour à tous. On fait le point sur la livraison du lot 1.',
      ).drain<void>();

      final Map<String, dynamic> body = http.bodies.single!;
      expect(body.containsKey('output_config'), isFalse);
      expect(body['max_tokens'], kLlmAnswerMaxTokens);
    });

    test('coach : inchangé (pas d\'effort, max_tokens habituel)', () async {
      final RecordingHttpAdapter http = RecordingHttpAdapter(
        reply: BodyReply(200, kOkStream[LlmProviderId.anthropic]!),
      );
      try {
        await coachEnglish(
          provider(LlmProviderId.anthropic, http),
          'I am agree with you.',
        );
      } on Object {
        // « OK » n'est pas un retour du coach : seule la requête compte ici.
      }

      final Map<String, dynamic> body = http.bodies.single!;
      expect(body.containsKey('output_config'), isFalse);
      expect(body['max_tokens'], kLlmAnswerMaxTokens);
    });

    test('la même requête sans la propriété de latence : pas d\'effort (la '
        'propriété est portée par la requête du direct)', () async {
      final LlmChatRequest live = await liveRequestVia(ScriptedLlmProvider());

      final Map<String, dynamic> body = await bodyOf(
        LlmProviderId.anthropic,
        plainCopy(live),
      );

      expect(body.containsKey('output_config'), isFalse);
    });
  });

  group('autres fournisseurs : propriété ignorée, sans erreur', () {
    for (final LlmProviderId id in <LlmProviderId>[
      LlmProviderId.openai,
      LlmProviderId.gemini,
      LlmProviderId.ollama,
    ]) {
      test('${id.name} : corps identique à celui de la même requête sans '
          'elle, aucun champ d\'effort', () async {
        final LlmChatRequest live = await liveRequestVia(ScriptedLlmProvider());

        final Map<String, dynamic> withIt = await bodyOf(id, live);
        final Map<String, dynamic> without = await bodyOf(id, plainCopy(live));

        expect(jsonEncode(withIt), jsonEncode(without));
        final String encoded = jsonEncode(withIt);
        for (final String field in <String>[
          'output_config',
          'effort',
          'reasoning_effort',
          'thinking',
        ]) {
          expect(encoded, isNot(contains('"$field"')), reason: field);
        }
      });
    }
  });
}
