import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_key_store.provider.g.dart';

/// Provider singleton pour [ApiKeyStore] (trousseau macOS).
@Riverpod(keepAlive: true)
ApiKeyStore apiKeyStore(Ref ref) => KeychainApiKeyStore();
