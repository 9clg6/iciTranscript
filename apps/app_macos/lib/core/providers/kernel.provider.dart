import 'package:core_data/database/app_database.dart';
import 'package:core_foundation/logging/logger.dart';
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

  // Le serveur ML est demarre par LiveTranscriptionService au moment du recording
  // Ollama est initialise par OllamaSetupViewModel au demarrage
  log.info('Kernel initialise');
}
