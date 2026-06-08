import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ollama.service.provider.g.dart';

/// Provider singleton pour [OllamaService].
@Riverpod(keepAlive: true)
OllamaService ollamaService(Ref ref) {
  final OllamaService service = OllamaService();
  ref.onDispose(service.dispose);
  return service;
}
