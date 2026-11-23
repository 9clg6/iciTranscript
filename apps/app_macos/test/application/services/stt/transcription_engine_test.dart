import 'dart:async';
import 'dart:io';

import 'package:core_data/clients/mistral_realtime_client.dart';
import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/enum/transcription_health.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';

import '../../../helpers/live_service_fakes.dart';
import '../../../helpers/settings_fakes.dart';

// Moteur de transcription au choix : « Sur ce Mac » (voxmlx local, 7 Go de
// mémoire) ou « Mistral (en ligne) ». Coupé par défaut. Mistral n'est
// utilisable qu'avec l'interrupteur d'envoi en ligne ALLUMÉ et une clé
// Mistral rangée au trousseau (compte `mistral`, comme KeychainPlugin :
// service = bundle id). Moteur en ligne choisi : la note ne démarre JAMAIS
// le serveur local et ne touche pas à ses ports (c'est le but : pas de
// 7 Go).
//
// API supposée (lib/application/services/stt/transcription_engine.dart) :
// - `enum TranscriptionEngine { local, mistral }` ;
// - `TranscriptionEngineSettings.fromPrefs(Map<String, Object?>)`,
//   `static const String engineKey = 'transcription_engine'`, champ
//   `engine` (défaut `local`) ;
// - `enum TranscriptionEngineRefusal { cloudNotAllowed, missingKey }` ;
// - `TranscriptionEngineSelection(ApiKeyStore keys).resolve({required
//   TranscriptionEngine chosen, required bool cloudAllowed})` rend
//   `({TranscriptionEngine engine, TranscriptionEngineRefusal? refusal})` ;
// - `LlmProviderId.mistral` : la clé Mistral (une seule, compte trousseau
//   `mistral`) ;
// - `LiveTranscriptionService.startTranscription(..., engine:)` ;
// - `TranscriptionHealth.keyRejected` : « clé refusée », visible.
// L'interrupteur d'envoi en ligne est celui de l'IA (`llm_cloud_allowed`).
const String _key = 'mistral-test-SECRET-0123456789';

void main() {
  group('choix du moteur', () {
    test('par défaut, et pour une valeur absente ou inattendue : sur ce '
        'Mac', () {
      expect(
        TranscriptionEngineSettings.fromPrefs(<String, Object?>{}).engine,
        TranscriptionEngine.local,
      );
      expect(
        TranscriptionEngineSettings.fromPrefs(<String, Object?>{
          TranscriptionEngineSettings.engineKey: 42,
        }).engine,
        TranscriptionEngine.local,
      );
      expect(
        TranscriptionEngineSettings.fromPrefs(<String, Object?>{
          TranscriptionEngineSettings.engineKey: 'mistral',
        }).engine,
        TranscriptionEngine.mistral,
      );
    });

    test('la clé Mistral est au trousseau sous le compte « mistral »', () {
      expect(LlmProviderId.mistral.name, 'mistral');
    });

    for (final (bool cloud, bool key, TranscriptionEngine engine, Object? why)
        in <(bool, bool, TranscriptionEngine, Object?)>[
          (
            false,
            true,
            TranscriptionEngine.local,
            TranscriptionEngineRefusal.cloudNotAllowed,
          ),
          (
            true,
            false,
            TranscriptionEngine.local,
            TranscriptionEngineRefusal.missingKey,
          ),
          (
            false,
            false,
            TranscriptionEngine.local,
            TranscriptionEngineRefusal.cloudNotAllowed,
          ),
          (true, true, TranscriptionEngine.mistral, null),
        ]) {
      test('Mistral choisi, envoi en ligne ${cloud ? 'permis' : 'coupé'}, '
          '${key ? 'clé rangée' : 'sans clé'} : ${engine.name}'
          '${why == null ? '' : ' (refus : $why)'}', () async {
        final InMemoryApiKeyStore keys = InMemoryApiKeyStore();
        if (key) await keys.write(LlmProviderId.mistral, _key);
        final ({
          TranscriptionEngine engine,
          TranscriptionEngineRefusal? refusal,
        })
        r = await TranscriptionEngineSelection(
          keys,
        ).resolve(chosen: TranscriptionEngine.mistral, cloudAllowed: cloud);
        expect(r.engine, engine);
        expect(r.refusal, why);
      });
    }

    test(
      'sur ce Mac choisi : jamais en ligne, même permis et avec une clé',
      () async {
        final InMemoryApiKeyStore keys = InMemoryApiKeyStore();
        await keys.write(LlmProviderId.mistral, _key);
        final ({
          TranscriptionEngine engine,
          TranscriptionEngineRefusal? refusal,
        })
        r = await TranscriptionEngineSelection(
          keys,
        ).resolve(chosen: TranscriptionEngine.local, cloudAllowed: true);
        expect(r.engine, TranscriptionEngine.local);
        expect(r.refusal, isNull);
      },
    );
  });

  group('une note avec le moteur en ligne', () {
    test('ne démarre pas le serveur local et ne vise pas ses ports', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async);
        unawaited(
          h.service.startTranscription(
            serverCommand: LiveServiceHarness.command,
            serverArgs: LiveServiceHarness.args,
            engine: TranscriptionEngine.mistral,
          ),
        );
        async.elapse(const Duration(seconds: 5));
        expect(h.process.starts, isEmpty, reason: 'pas de voxmlx');
        expect(h.fakeRemote.connectedUrls, isNotEmpty);
        for (final String url in h.fakeRemote.connectedUrls) {
          expect(url, isNot(contains('localhost')));
          expect(url, isNot(contains('127.0.0.1')));
        }
        h.stop();
        expect(h.process.starts, isEmpty);
      });
    });

    test('garde : le moteur local démarre toujours son serveur', () {
      fakeAsync((FakeAsync async) {
        final LiveServiceHarness h = LiveServiceHarness(async);
        unawaited(
          h.service.startTranscription(
            serverCommand: LiveServiceHarness.command,
            serverArgs: LiveServiceHarness.args,
            engine: TranscriptionEngine.local,
          ),
        );
        async.elapse(const Duration(seconds: 5));
        expect(h.process.starts, hasLength(1));
      });
    });

    test('clé refusée par Mistral : état « clé refusée » visible, pas de '
        'tempête de reconnexions', () {
      fakeAsync((FakeAsync async) {
        int attempts = 0;
        WebSocketClient refusing(Map<String, String> headers) =>
            _Refusing(() => attempts++);
        final LiveServiceHarness h = LiveServiceHarness(
          async,
          remote: TranscriptionRemoteDataSourceImpl(
            micClient: MistralRealtimeClient(
              apiKey: () async => _key,
              transport: refusing,
            ),
            systemClient: MistralRealtimeClient(
              apiKey: () async => _key,
              transport: refusing,
            ),
          ),
        );
        final List<TranscriptionHealth> health = <TranscriptionHealth>[];
        h.service.transcriptionHealthStream.listen(health.add);
        unawaited(
          h.service
              .startTranscription(
                serverCommand: LiveServiceHarness.command,
                serverArgs: LiveServiceHarness.args,
                engine: TranscriptionEngine.mistral,
              )
              .catchError((Object _) {}),
        );
        async.elapse(const Duration(minutes: 5));
        expect(health, contains(TranscriptionHealth.keyRejected));
        expect(attempts, lessThanOrEqualTo(4), reason: '$attempts essais');
        expect(h.process.starts, isEmpty);
      });
    });
  });
}

final class _Refusing extends WebSocketClient {
  _Refusing(this._onAttempt);

  final void Function() _onAttempt;

  @override
  Future<void> connect(String url) async {
    _onAttempt();
    throw WebSocketException(
      "Connection to '$url' was not upgraded to websocket, HTTP status "
      'code: 401',
    );
  }
}
