import 'package:dio/dio.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ollama.service.provider.g.dart';

/// Provider singleton pour [OllamaService] : le démon passe par le registre
/// des serveurs de l'app (seul celui qu'on a lancé est arrêté).
@Riverpod(keepAlive: true)
OllamaService ollamaService(Ref ref) {
  final Dio dio = Dio();
  final OllamaService service = OllamaService(
    processes: ref.watch(ownedProcessRegistryProvider),
    dio: dio,
  );
  ref.onDispose(() {
    service.dispose();
    dio.close();
  });
  return service;
}
