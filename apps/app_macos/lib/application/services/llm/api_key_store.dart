import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

/// Stockage des cles API des fournisseurs LLM.
abstract interface class ApiKeyStore {
  /// Cle de [provider], null si absente.
  Future<String?> read(LlmProviderId provider);

  /// Range [key] sans les blancs autour ; une cle vide supprime la cle.
  Future<void> write(LlmProviderId provider, String key);

  /// Supprime la cle de [provider].
  Future<void> delete(LlmProviderId provider);
}

/// Cles rangees dans le trousseau macOS (plugin Swift `KeychainPlugin`).
///
/// Jamais de fichier ni de journal : la cle ne transite que par le canal.
class KeychainApiKeyStore implements ApiKeyStore {
  /// Cree un [KeychainApiKeyStore].
  KeychainApiKeyStore();

  static const MethodChannel _channel = MethodChannel(
    'com.icitranscript/keychain',
  );

  @override
  Future<String?> read(LlmProviderId provider) {
    return _channel.invokeMethod<String>('readKey', <String, String>{
      'provider': provider.name,
    });
  }

  @override
  Future<void> write(LlmProviderId provider, String key) {
    final String trimmed = key.trim();
    if (trimmed.isEmpty) return delete(provider);
    return _channel.invokeMethod<void>('writeKey', <String, String>{
      'provider': provider.name,
      'key': trimmed,
    });
  }

  @override
  Future<void> delete(LlmProviderId provider) {
    return _channel.invokeMethod<void>('deleteKey', <String, String>{
      'provider': provider.name,
    });
  }
}

/// Fournisseur actif et etat "configure", deduits des cles rangees.
class LlmProviderSelection {
  /// Cree une [LlmProviderSelection] sur [_store].
  LlmProviderSelection(this._store);

  final ApiKeyStore _store;

  /// Ordre de repli quand l'utilisateur n'a pas choisi.
  static const List<LlmProviderId> _cloudOrder = <LlmProviderId>[
    LlmProviderId.anthropic,
    LlmProviderId.openai,
    LlmProviderId.gemini,
  ];

  /// Ollama (local) est toujours configure ; un fournisseur cloud l'est
  /// quand sa cle est rangee.
  Future<bool> isConfigured(LlmProviderId provider) async {
    return provider == LlmProviderId.ollama ||
        await _store.read(provider) != null;
  }

  /// [preferred] s'il est configure, sinon le premier fournisseur cloud
  /// configure, sinon Ollama.
  Future<LlmProviderId> activeProvider({LlmProviderId? preferred}) async {
    if (preferred != null && await isConfigured(preferred)) return preferred;
    for (final LlmProviderId provider in _cloudOrder) {
      if (await isConfigured(provider)) return provider;
    }
    return LlmProviderId.ollama;
  }
}
