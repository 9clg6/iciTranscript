import 'dart:async';
import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/summary.dao.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';

import 'local_model_fakes.dart';
import 'settings_fakes.dart';

/// Fournisseur LLM scripté : garde chaque requête et répond par [reply]
/// (index = rang de la requête, à partir de 0). Aucun réseau.
class ScriptedLlmProvider implements LlmProvider {
  ScriptedLlmProvider(this.reply);

  final Stream<String> Function(LlmChatRequest request, int index) reply;
  final List<LlmChatRequest> requests = <LlmChatRequest>[];

  @override
  Stream<String> streamChat(LlmChatRequest request) {
    requests.add(request);
    return reply(request, requests.length - 1);
  }
}

/// Tout le texte envoyé par [request] (consignes + messages).
String requestText(LlmChatRequest request) => <String>[
  request.systemPrompt,
  for (final LlmMessage m in request.messages) m.content,
].join('\n');

/// Réponse en streaming de [id] dont le texte est [text] (format réel de
/// l'API, d'après [kOkStream]).
String streamOf(LlmProviderId id, String text) =>
    kOkStream[id]!.replaceFirst('"OK"', jsonEncode(text));

/// Modèles choisis dans Réglages pour les tests (distincts des défauts, pour
/// prouver lequel est rangé avec le résumé).
const String kClaudeTestModel = 'claude-test-model';
const String kLocalTestModel = 'mistral-test-model';

/// Écrit les choix LLM dans prefs.json (dossier de test), avant tout
/// conteneur : `activeLlmProvider` est gardé en vie après sa 1re lecture.
Future<void> writeLlmPrefs({
  required bool cloudAllowed,
  LlmProviderId? preferred,
}) async {
  resetPrefs();
  await PrefsStore().update(<String, Object?>{
    LlmSettings.cloudAllowedKey: cloudAllowed,
    if (preferred != null) LlmSettings.providerKey: preferred.name,
    LlmSettings.modelsKey: <String, String>{
      LlmProviderId.anthropic.name: kClaudeTestModel,
      LlmProviderId.ollama.name: kLocalTestModel,
    },
  });
}

/// Segment de la note `s1`.
TranscriptSegmentEntity noteSegment(
  int i,
  String text, {
  AudioSource source = AudioSource.output,
}) => TranscriptSegmentEntity(
  id: 'seg-$i',
  sessionId: 's1',
  source: source,
  text: text,
  timestampMs: i * 5000,
  createdAt: DateTime(2026, 11, 20, 9),
);

/// Une réunion courte : une phrase de l'utilisateur (micro), une de
/// l'interlocuteur (audio système).
final List<TranscriptSegmentEntity> kShortMeeting = <TranscriptSegmentEntity>[
  noteSegment(0, 'I am agree with you.', source: AudioSource.input),
  noteSegment(1, 'We need the budget by Friday.'),
];

/// Crée la note `s1` et ses [segments] par les vrais dépôts de [c].
Future<void> seedNote(
  ProviderContainer c,
  List<TranscriptSegmentEntity> segments,
) async {
  final DateTime start = DateTime(2026, 11, 20, 9);
  await c
      .read(sessionRepositoryProvider)
      .create(
        SessionEntity(
          id: 's1',
          title: 'Point budget',
          createdAt: start,
          updatedAt: start,
          durationSeconds: 3600,
          status: SessionStatus.completed,
        ),
      );
  await c.read(transcriptRepositoryProvider).saveBatch(segments);
}

/// Ligne rangée dans `summaries` pour `s1`, null si aucune.
Future<Summary?> storedRow(AppDatabase db) => SummaryDao(db).getBySessionId('s1');

/// Enveloppe rangée pour `s1` (vide si aucune ligne).
Future<SessionAnalysis> storedAnalysis(AppDatabase db) async =>
    SessionAnalysis.fromStored((await storedRow(db))?.content);

/// Retour du coach au format attendu par `EnglishFeedbackEntity.fromJson`.
const Map<String, Object?> kFeedbackJson = <String, Object?>{
  'overall': 'Bon niveau général.',
  'corrections': <Map<String, String>>[
    <String, String>{
      'original': 'I am agree',
      'corrected': 'I agree',
      'category': 'grammar',
      'explanation': '« agree » est un verbe.',
    },
  ],
};

/// Trousseau en mémoire qui compte les lectures par fournisseur (chaque
/// lecture peut afficher une invite du trousseau sur un build ad hoc).
class CountingApiKeyStore extends InMemoryApiKeyStore {
  CountingApiKeyStore([super.keys]);

  final List<LlmProviderId> reads = <LlmProviderId>[];

  /// Lectures des fournisseurs en ligne.
  List<LlmProviderId> get cloudReads =>
      reads.where((LlmProviderId id) => id != LlmProviderId.ollama).toList();

  @override
  Future<String?> read(LlmProviderId provider) {
    reads.add(provider);
    return super.read(provider);
  }
}

/// Modèle local installé mais démon arrêté : [ensureReady] le démarre
/// (compte, garde le nombre de requêtes déjà parties à ce moment), échoue
/// avec [startError], ou ne répond jamais si [hangOnStart].
class StoppedDaemonOllamaService extends InstantOllamaService {
  StoppedDaemonOllamaService({
    required this.sentSoFar,
    this.startError,
    this.hangOnStart = false,
  }) : super(installed: true);

  /// Nombre de requêtes LLM déjà envoyées (lu au démarrage du démon).
  final int Function() sentSoFar;
  final Object? startError;
  final bool hangOnStart;

  bool running = false;
  final List<int> sentAtStart = <int>[];

  @override
  Future<bool> isFullyReady() async => running;

  @override
  Future<void> ensureReady({
    void Function(OllamaSetupStage stage, double progress)? onProgress,
  }) async {
    ensureReadyCalls++;
    sentAtStart.add(sentSoFar());
    if (hangOnStart) return Completer<void>().future;
    if (startError case final Object e) throw e;
    running = true;
  }
}
