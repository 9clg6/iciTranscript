import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/audio_capture_channel.dart';

import 'fake_data.dart';

/// prefs.json du processus de test (dossier temporaire, jamais le vrai).
File get prefsFile => File('${appDataDirectory()}/prefs.json');

/// Repart d'un prefs.json absent.
void resetPrefs() {
  if (prefsFile.existsSync()) prefsFile.deleteSync();
}

/// Contenu décodé de prefs.json ; échoue si le fichier n'est pas un objet
/// JSON valide.
Map<String, dynamic> readPrefs() =>
    jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;

/// Réessaie [check] jusqu'à ce qu'il passe ou que [timeout] expire (écritures
/// de fichier non attendues par l'appelant).
Future<void> eventually(
  FutureOr<void> Function() check, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (true) {
    try {
      await check();
      return;
    } on Object {
      if (DateTime.now().isAfter(end)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Trousseau en mémoire : survit à un « redémarrage » (nouveau conteneur)
/// tant que le test garde la même instance. Même contrat que le vrai :
/// clé rangée sans blancs, clé vide = suppression.
class InMemoryApiKeyStore implements ApiKeyStore {
  InMemoryApiKeyStore([Map<LlmProviderId, String>? keys])
    : keys = keys ?? <LlmProviderId, String>{};

  final Map<LlmProviderId, String> keys;

  /// Simule un refus du trousseau (signature ad hoc, accès refusé).
  bool refuseWrites = false;
  bool refuseReads = false;
  int writeCalls = 0;
  int deleteCalls = 0;

  PlatformException get _refused => PlatformException(
    code: 'errSecAuthFailed',
    message: 'User interaction is not allowed.',
  );

  @override
  Future<String?> read(LlmProviderId provider) async {
    if (refuseReads) throw _refused;
    return keys[provider];
  }

  @override
  Future<void> write(LlmProviderId provider, String key) async {
    writeCalls++;
    if (refuseWrites) throw _refused;
    final String trimmed = key.trim();
    if (trimmed.isEmpty) {
      keys.remove(provider);
    } else {
      keys[provider] = trimmed;
    }
  }

  @override
  Future<void> delete(LlmProviderId provider) async {
    deleteCalls++;
    if (refuseWrites) throw _refused;
    keys.remove(provider);
  }
}

/// Réponse rejouée par [RecordingHttpAdapter].
sealed class FakeReply {
  const FakeReply();
}

/// Statut [status] et corps [body] (complet, puis fin).
final class BodyReply extends FakeReply {
  const BodyReply(this.status, this.body, {this.keepOpen = false});
  final int status;
  final String body;

  /// Le corps ne se termine jamais (serveur muet après [body]).
  final bool keepOpen;
}

/// Réseau coupé (comme `IOHttpClientAdapter` sur `SocketException`).
final class UnreachableReply extends FakeReply {
  const UnreachableReply();
}

/// Aucune réponse, jamais (pas même les en-têtes).
final class HangReply extends FakeReply {
  const HangReply();
}

/// Transport Dio factice qui garde TOUTES les requêtes reçues et répond
/// d'après [reply] (par défaut 200, corps vide). Aucun appel réseau.
class RecordingHttpAdapter implements HttpClientAdapter {
  RecordingHttpAdapter({this.reply = const BodyReply(200, '')});

  FakeReply reply;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Map<String, dynamic>?> bodies = <Map<String, dynamic>?>[];
  int aborts = 0;

  /// Hôte de la dernière requête, null si aucune.
  String? get lastHost => requests.isEmpty ? null : requests.last.uri.host;

  /// Valeur d'un en-tête de la dernière requête, sans tenir compte de la casse.
  String? lastHeader(String name) {
    for (final MapEntry<String, dynamic> e in requests.last.headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return '${e.value}';
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    Map<String, dynamic>? body;
    if (requestStream != null) {
      final List<int> bytes = await requestStream
          .expand((Uint8List c) => c)
          .toList();
      body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } else if (options.data is Map) {
      body = Map<String, dynamic>.from(options.data as Map<dynamic, dynamic>);
    }
    bodies.add(body);
    unawaited(cancelFuture?.whenComplete(() => aborts++));

    switch (reply) {
      case UnreachableReply():
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
          error: const SocketException('Connection refused'),
        );
      case HangReply():
        return Completer<ResponseBody>().future;
      case BodyReply(:final int status, body: final String text, :final bool keepOpen):
        final StreamController<Uint8List> controller =
            StreamController<Uint8List>(onCancel: () => aborts++);
        () async {
          await Future<void>.delayed(Duration.zero);
          if (text.isNotEmpty) controller.add(utf8.encode(text));
          if (!keepOpen) await controller.close();
        }();
        return ResponseBody(
          controller.stream,
          status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/event-stream'],
          },
        );
    }
  }

  @override
  void close({bool force = false}) {}
}

/// Capture audio factice avec deux micros (mic-1, mic-2) et une sortie.
class DevicesAudioChannel extends AudioCaptureChannel {
  @override
  Future<List<AudioDeviceEntity>> listDevices() async =>
      FakeData.createAudioDeviceList();

  @override
  Future<void> startCapture({
    String? inputDeviceId,
    bool outputEnabled = false,
  }) async {}

  @override
  Future<void> stopCapture() async {}

  @override
  Future<bool> isSystemAudioAvailable() async => true;

  @override
  Future<Map<String, String>> checkPermissions() async => <String, String>{
    'mic': 'authorized',
    'screenRecording': 'authorized',
  };

  @override
  Future<void> openSystemSettings(String pane) async {}
}

/// Hôte appelé par chaque fournisseur.
const Map<LlmProviderId, String> kProviderHost = <LlmProviderId, String>{
  LlmProviderId.anthropic: 'api.anthropic.com',
  LlmProviderId.openai: 'api.openai.com',
  LlmProviderId.gemini: 'generativelanguage.googleapis.com',
  LlmProviderId.ollama: 'localhost',
};

/// Plus petite réponse en streaming valide de chaque fournisseur : un mot.
const Map<LlmProviderId, String> kOkStream = <LlmProviderId, String>{
  LlmProviderId.anthropic:
      'event: content_block_delta\n'
      'data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "OK"}}\n'
      '\n'
      'event: message_stop\n'
      'data: {"type": "message_stop"}\n'
      '\n',
  LlmProviderId.openai:
      'data: {"choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":null}]}\n'
      '\n'
      'data: [DONE]\n'
      '\n',
  LlmProviderId.gemini:
      'data: {"candidates": [{"content": {"parts": [{"text": "OK"}],"role": "model"},"finishReason": "STOP"}]}\n'
      '\n',
  // API compatible OpenAI.
  LlmProviderId.mistral:
      'data: {"choices":[{"index":0,"delta":{"content":"OK"},"finish_reason":null}]}\n'
      '\n'
      'data: [DONE]\n'
      '\n',
  LlmProviderId.ollama:
      '{"model":"mistral","message":{"role":"assistant","content":"OK"},"done":false}\n'
      '{"model":"mistral","message":{"role":"assistant","content":""},"done":true}\n',
};

/// Requête minimale envoyée par les tests.
const LlmChatRequest kPing = LlmChatRequest(
  systemPrompt: 'Réponds OK.',
  messages: <LlmMessage>[LlmMessage(role: LlmRole.user, content: 'Ping')],
  maxTokens: 5,
);

/// Envoie [kPing] par [provider] et vide la réponse ; une erreur est rendue,
/// pas levée.
Future<Object?> sendPing(LlmProvider provider) async {
  try {
    await provider.streamChat(kPing).drain<void>();
    return null;
  } on Object catch (e) {
    return e;
  }
}
