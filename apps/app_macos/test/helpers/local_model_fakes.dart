import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/services/ollama.service.provider.dart';

/// Ollama factice qui répond tout de suite : aucun réseau, process ni disque.
///
/// [ensureReady] compte les appels (installation / téléchargement possible) ;
/// quand [installed] est faux, un tel appel est précisément le défaut.
class InstantOllamaService extends OllamaService {
  InstantOllamaService({required this.installed});

  final bool installed;
  int ensureReadyCalls = 0;
  int summarizeCalls = 0;
  int analyzeCalls = 0;

  static const String summary = 'Résumé de la réunion.';
  static const EnglishFeedbackEntity feedback = EnglishFeedbackEntity(
    overall: 'Bon niveau général.',
    corrections: <EnglishCorrectionEntity>[
      EnglishCorrectionEntity(
        original: 'I am agree',
        corrected: 'I agree',
        category: 'grammar',
        explanation: '« agree » est un verbe.',
      ),
    ],
  );

  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<bool> isFullyReady() async => installed;

  @override
  Future<void> ensureReady({
    void Function(OllamaSetupStage stage, double progress)? onProgress,
  }) async {
    ensureReadyCalls++;
  }

  @override
  Future<String> summarize(String transcript) async {
    summarizeCalls++;
    return summary;
  }

  @override
  Future<EnglishFeedbackEntity> analyzeEnglish(String transcript) async {
    analyzeCalls++;
    return feedback;
  }

  @override
  Future<void> unloadModel() async {}

  @override
  Future<void> dispose() async {}
}

/// Base Drift en mémoire + Ollama factice : rien ne touche le vrai dossier.
List<Override> localModelOverrides(
  AppDatabase db,
  InstantOllamaService ollama,
) => <Override>[
  databaseProvider.overrideWithValue(db),
  ollamaServiceProvider.overrideWithValue(ollama),
];

/// Nouvelle base en mémoire.
AppDatabase memoryDatabase() => AppDatabase(NativeDatabase.memory());
