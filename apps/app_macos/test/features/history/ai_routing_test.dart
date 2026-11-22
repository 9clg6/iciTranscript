import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';

import '../../helpers/llm_fakes.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Résumer et Coach anglais depuis la note passent par le fournisseur actif
/// (besoins B7 et B10) : aujourd'hui ils appellent Ollama en direct, et
/// choisir Claude dans Réglages ne change rien.
///
/// Monde de test : vrai `activeLlmProvider` (prefs.json + trousseau en
/// mémoire), transport Dio factice (`llmDioProvider`), Ollama factice
/// (installé ou non), base en mémoire. Le fournisseur visé = hôte des
/// requêtes reçues.
///
/// API supposée : `SessionDetailViewModel.generateSummary()` et
/// `analyzeEnglish()` (existants) se terminent quand la réponse est finie et
/// rangée ; le modèle rangé dans `summaries.model` est celui de la requête
/// (`LlmSettings.modelFor` du fournisseur utilisé).
void main() {
  late AppDatabase db;
  late InMemoryApiKeyStore store;
  late RecordingHttpAdapter adapter;
  late InstantOllamaService ollama;

  const String claudeKey = 'sk-ant-test-SECRET-0123456789';
  final String claude = kProviderHost[LlmProviderId.anthropic]!;
  final String local = kProviderHost[LlmProviderId.ollama]!;
  const String summaryText = 'Le budget est attendu vendredi.';

  /// [key] : clé Claude rangée ; [cloud] : envoi autorisé ; [installed] :
  /// modèle local installé. Rend le view model de la note `s1`, chargé.
  Future<(ProviderContainer, SessionDetailViewModelProvider)> openNote({
    required bool key,
    required bool cloud,
    required bool installed,
  }) async {
    await writeLlmPrefs(
      cloudAllowed: cloud,
      preferred: key ? LlmProviderId.anthropic : null,
    );
    db = memoryDatabase();
    store = InMemoryApiKeyStore(<LlmProviderId, String>{
      if (key) LlmProviderId.anthropic: claudeKey,
    });
    adapter = RecordingHttpAdapter();
    ollama = InstantOllamaService(installed: installed);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, ollama),
        apiKeyStoreProvider.overrideWithValue(store),
        llmDioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await seedNote(c, kShortMeeting);
    final SessionDetailViewModelProvider note = sessionDetailViewModelProvider(
      sessionId: 's1',
    );
    c.listen(note, (_, _) {});
    await c.read(note.future);
    return (c, note);
  }

  SessionDetailState stateOf(
    ProviderContainer c,
    SessionDetailViewModelProvider note,
  ) => c.read(note).value!;

  Set<String> hosts() =>
      adapter.requests.map((RequestOptions r) => r.uri.host).toSet();

  group('Résumer', () {
    test('Claude configuré, autorisé et choisi : la requête part chez Claude, '
        'avec sa clé ; le résumé est affiché et rangé avec son modèle', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: true, installed: true);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, summaryText),
      );

      await c.read(note.notifier).generateSummary();

      expect(hosts(), <String>{claude});
      expect(adapter.lastHeader('x-api-key'), claudeKey);
      expect(adapter.bodies.last?['model'], kClaudeTestModel);
      expect(stateOf(c, note).summary, summaryText);
      expect((await storedAnalysis(db)).summary, summaryText);
      expect((await storedRow(db))?.model, kClaudeTestModel);
      expect(ollama.ensureReadyCalls, 0, reason: 'Ollama inutile ici');
    });

    test('Claude utilisable et modèle local absent : le résumé marche quand '
        'même, sans rien télécharger', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: true, installed: false);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, summaryText),
      );

      await c.read(note.notifier).generateSummary();

      expect(hosts(), <String>{claude});
      expect(stateOf(c, note).summary, summaryText);
      expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
    });

    test('clé Claude rangée mais envoi coupé : le modèle local répond, rien '
        'ne part en ligne ; son modèle est rangé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: false, installed: true);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.ollama, summaryText),
      );

      await c.read(note.notifier).generateSummary();

      expect(hosts(), <String>{local});
      expect(adapter.bodies.last?['model'], kLocalTestModel);
      expect(stateOf(c, note).summary, summaryText);
      expect((await storedRow(db))?.model, kLocalTestModel);
    });

    test('envoi autorisé mais aucune clé : le modèle local répond', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: false, cloud: true, installed: true);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.ollama, summaryText),
      );

      await c.read(note.notifier).generateSummary();

      expect(hosts(), <String>{local});
      expect(stateOf(c, note).summary, summaryText);
    });

    test('clé rangée, envoi coupé, modèle local absent : rien n\'est envoyé, '
        'rien n\'est téléchargé, aucun résumé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: false, installed: false);

      await c.read(note.notifier).generateSummary();

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
      expect(stateOf(c, note).summary, isNull);
      expect(stateOf(c, note).isSummaryLoading, isFalse);
      expect(await storedRow(db), isNull);
    });

    test('ni clé ni modèle local : rien n\'est envoyé, aucun résumé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: false, cloud: true, installed: false);

      await c.read(note.notifier).generateSummary();

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0);
      expect(stateOf(c, note).summary, isNull);
    });
  });

  group('Coach anglais', () {
    test('Claude configuré et autorisé : la requête part chez Claude avec la '
        'seule parole du micro ; le retour est lu et rangé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: true, installed: false);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.anthropic, jsonEncode(kFeedbackJson)),
      );

      await c.read(note.notifier).analyzeEnglish();

      expect(hosts(), <String>{claude});
      final String sent = jsonEncode(adapter.bodies.last);
      expect(sent, contains('I am agree with you.'));
      expect(sent, isNot(contains('budget by Friday')),
          reason: 'le coach ne corrige que ce que l\'utilisateur a dit');
      expect(
        stateOf(c, note).feedback?.corrections.single.corrected,
        'I agree',
      );
      final SessionAnalysis saved = await storedAnalysis(db);
      expect(saved.feedback?.corrections.single.corrected, 'I agree');
    });

    test('envoi coupé, modèle local installé : le modèle local répond', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: false, installed: true);
      adapter.reply = BodyReply(
        200,
        streamOf(LlmProviderId.ollama, jsonEncode(kFeedbackJson)),
      );

      await c.read(note.notifier).analyzeEnglish();

      expect(hosts(), <String>{local});
      expect(stateOf(c, note).feedback?.overall, 'Bon niveau général.');
    });

    test('rien de disponible : rien n\'est envoyé ni téléchargé', () async {
      final (ProviderContainer c, SessionDetailViewModelProvider note) =
          await openNote(key: true, cloud: false, installed: false);

      await c.read(note.notifier).analyzeEnglish();

      expect(adapter.requests, isEmpty);
      expect(ollama.ensureReadyCalls, 0);
      expect(stateOf(c, note).feedback, isNull);
    });
  });
}
