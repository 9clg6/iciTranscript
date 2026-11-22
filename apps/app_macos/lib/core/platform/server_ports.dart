import 'dart:io';

import 'package:ici_transcript/core/platform/app_data_directory.dart';

/// Port d'Ollama : un seul démon, partagé entre dev et release.
const int ollamaPort = 11434;

/// URL de base d'Ollama (localhost, comme avant).
final Uri ollamaBaseUrl = Uri.parse('http://localhost:$ollamaPort');

/// Ports des serveurs lancés par l'app pour ce lancement, et URL clientes
/// qui en dérivent. Seul fichier où ces ports s'écrivent.
final class ServerPorts {
  const ServerPorts._({required this.transcription, required this.diarization});

  /// voxmlx-serve.
  final int transcription;

  /// nemotron_diar_mlx.server.
  final int diarization;

  /// Ollama (partagé).
  int get ollama => ollamaPort;

  /// WebSocket de transcription.
  Uri get transcriptionWebSocket =>
      Uri.parse('ws://127.0.0.1:$transcription/v1/realtime');

  /// Santé du serveur de transcription.
  Uri get transcriptionHealth =>
      Uri.parse('http://127.0.0.1:$transcription/health');

  /// WebSocket de diarization en direct.
  Uri get diarizationWebSocket =>
      Uri.parse('ws://127.0.0.1:$diarization/v1/diarize');

  /// Santé du serveur de diarization en direct.
  Uri get diarizationHealth =>
      Uri.parse('http://127.0.0.1:$diarization/health');

  /// Base d'Ollama.
  Uri get ollamaBase => ollamaBaseUrl;
}

/// Release : 8000/8001 (ceux d'aujourd'hui). Données de dev (debug, profile,
/// `OATS_DATA_DIR`) : 8100/8101, pour ne pas se battre avec l'app installée.
ServerPorts resolveServerPorts(
  Map<String, String> environment, {
  required AppBuildMode buildMode,
}) => usesDevDataDirectory(environment, buildMode: buildMode)
    ? const ServerPorts._(transcription: 8100, diarization: 8101)
    : const ServerPorts._(transcription: 8000, diarization: 8001);

/// Ports de ce processus.
ServerPorts serverPorts() => resolveServerPorts(
  Platform.environment,
  buildMode: currentBuildMode,
);
