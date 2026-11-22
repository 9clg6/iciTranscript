import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/usecases/repair_interrupted_sessions.use_case.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/core/repositories/transcript.repository.provider.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
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
  // Jamais sous `flutter test` : la base et les WAV réels du développeur
  // sont sous ~/Library/Application Support/IciTranscript.
  if (!Platform.environment.containsKey('FLUTTER_TEST')) {
    await _repairAfterCrash(ref, log);
  }

  // Le serveur ML est demarre par LiveTranscriptionService au moment du recording
  // Ollama est initialise par OllamaSetupViewModel au demarrage
  log.info('Kernel initialise');
}

/// Répare ce qu'un arrêt brutal en pleine session a laissé : sessions
/// restées `active`, WAV dont l'en-tête n'a pas été finalisé. Un échec est
/// journalisé et ne bloque pas le lancement.
Future<void> _repairAfterCrash(Ref ref, Log log) async {
  try {
    await RepairInterruptedSessionsUseCase(
      sessionRepository: ref.read(sessionRepositoryProvider),
      transcriptRepository: ref.read(transcriptRepositoryProvider),
    ).invoke();
  } catch (e) {
    log.warning('Réparation des sessions interrompues échouée: $e');
  }

  final Directory recordings = Directory(
    LiveTranscriptionService.recordingsDir,
  );
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
