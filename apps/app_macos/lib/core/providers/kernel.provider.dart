import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'kernel.provider.g.dart';

/// Initialise les dependances au demarrage de l'application.
///
/// Le serveur ML (voxmlx-serve) est demarre par [LiveTranscriptionService]
/// au moment ou l'utilisateur lance un enregistrement.
/// Ollama est initialise separement par [OllamaSetupViewModel].
@Riverpod(keepAlive: true)
Future<void> kernel(Ref ref) async {
  final Log log = Log.named('Kernel');
  log.info('Initialisation du kernel...');

  // Initialiser la base de donnees
  // ignore: unused_local_variable
  final AppDatabase db = ref.watch(databaseProvider);
  log.info('Base de donnees initialisee');

  // Une fois au lancement, avant toute session : rien n'enregistre encore.
  // Les dossiers viennent de appDataDirectory() (temporaire sous test).
  await _repairAfterCrash(ref, log);

  // Serveurs laissés par un arrêt brutal : seulement ceux notés par cette
  // app dont le PID a encore la même identité. Ne lève jamais.
  await ref.read(ownedProcessRegistryProvider).cleanUpLeftovers();

  // Le serveur ML est demarre par LiveTranscriptionService au moment du recording
  // Ollama est initialise par OllamaSetupViewModel au demarrage
  log.info('Kernel initialise');
}

/// Répare ce qu'un arrêt brutal en pleine session a laissé : sessions
/// restées `active`, WAV dont l'en-tête n'a pas été finalisé. Ne supprime
/// rien. Un échec est journalisé et ne bloque pas le lancement.
Future<void> _repairAfterCrash(Ref ref, Log log) async {
  try {
    await RepairInterruptedSessionsUseCase(
      sessionRepository: ref.read(sessionRepositoryProvider),
      transcriptRepository: ref.read(transcriptRepositoryProvider),
    ).invoke();
  } catch (e) {
    log.warning('Réparation des sessions interrompues échouée: $e');
  }

  // Aucune suppression au lancement : les WAV d'un utilisateur existant ont
  // des mois, une purge automatique les effacerait tous au premier
  // lancement. RecordingRetention reste sans appelant ; un geste explicite
  // de l'utilisateur la déclenchera (tranche ultérieure).
  final String recordingsDir = LiveTranscriptionService.recordingsDir;
  final Directory recordings = Directory(recordingsDir);
  if (!recordings.existsSync()) return;
  for (final FileSystemEntity entry in recordings.listSync()) {
    if (entry is! File || !entry.path.endsWith('.wav')) continue;
    try {
      await WavRecorder.repair(entry.path);
    } catch (e) {
      log.warning('Réparation WAV échouée (${entry.path}): $e');
    }
  }
}
