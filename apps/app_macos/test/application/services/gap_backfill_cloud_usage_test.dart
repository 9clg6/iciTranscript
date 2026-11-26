import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/stt/mistral_batch_transcriber.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../fixtures/mistral_batch60.dart';
import '../../helpers/live_service_fakes.dart';

// Prix de la transcription en ligne (2026-11-26), part « rattrapage » : le
// rattrapage d'un repère par l'API batch de Mistral ajoute à la note l'audio
// que Mistral facture : `usage.prompt_audio_seconds` de la réponse
// (sonde batch60 : 60), sinon la longueur du PCM envoyé (16 kHz mono s16le
// = 32 octets/ms). Seulement sur un appel réussi (un appel refusé ou
// injoignable n'ajoute rien) ; un appel réussi qui ne retrouve rien est
// facturé quand même. Le moteur local n'ajoute rien. Additif : un
// rattrapage repris plus tard s'ajoute à ce qui est rangé.
//
// Montage comme le provider : GapBackfillService → EngineTranscriber
// (moteur lu à chaque appel) → MistralBatchTranscriber sur un faux Dio.
//
// API supposée (lib/application/services/gap_backfill.service.dart) :
// `abstract interface class BilledPcmTranscriber implements PcmTranscriber`
// avec `Future<({List<({int offsetMs, String text})> pieces, int billedMs})>
// transcribeBilled(Uint8List pcm)` ; `MistralBatchTranscriber` et
// `EngineTranscriber` l'implémentent (`EngineTranscriber` en local : la
// réponse du transcripteur local, `billedMs` 0) ; `transcribe` est
// inchangé. `GapBackfillService({..., SessionRepository? sessions})` :
// après chaque appel réussi d'un `BilledPcmTranscriber` avec `billedMs` >
// 0, `sessions.addCloudUsage(sessionId, batchMs: billedMs)`.
const String _key = 'mistral-test-SECRET-0123456789';
const String _session = '1700000000000';

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

/// Faux Mistral batch : répond par [reply] ; compte les appels réussis et
/// l'audio reçu (octets de données du WAV).
final class _Http implements HttpClientAdapter {
  _Http(this.reply);

  Future<ResponseBody> Function(int call, int wavMs) reply;
  int calls = 0;
  int succeeded = 0;
  int receivedMs = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Uint8List body = Uint8List.fromList(
      await requestStream!.expand((Uint8List c) => c).toList(),
    );
    final int at = latin1.decode(body).indexOf('RIFF');
    final int wavMs =
        ByteData.sublistView(body, at).getUint32(40, Endian.little) ~/ 32;
    receivedMs += wavMs;
    final ResponseBody r = await reply(++calls, wavMs);
    if (r.statusCode == 200) succeeded++;
    return r;
  }

  @override
  void close({bool force = false}) {}
}

/// Réponse réussie : une phrase au début, [seconds] d'audio facturé (null :
/// pas de champ `usage`).
ResponseBody _ok({num? seconds, bool empty = false}) =>
    _json(200, <String, Object>{
      'text': empty ? '' : 'Le budget est validé.',
      'segments': <Map<String, Object>>[
        if (!empty)
          <String, Object>{
            'text': ' Le budget est validé.',
            'start': 0.5,
            'end': 3.0,
          },
      ],
      if (seconds != null)
        'usage': <String, Object>{'prompt_audio_seconds': seconds},
    });

MistralBatchTranscriber _mistral(_Http http) => MistralBatchTranscriber(
  dio: Dio()..httpClientAdapter = http,
  apiKey: () async => _key,
);

Uint8List _voiced(int ms) {
  final Uint8List out = Uint8List(ms * 32);
  final ByteData d = ByteData.sublistView(out);
  for (int o = 0; o < out.length; o += 2) {
    d.setInt16(o, (o ~/ 2).isEven ? 1000 : -1000, Endian.little);
  }
  return out;
}

/// Transcripteur local (voxmlx) factice.
final class _Local implements PcmTranscriber {
  int calls = 0;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    return <({int offsetMs, String text})>[
      (offsetMs: 500, text: 'Le budget est validé.'),
    ];
  }
}

void main() {
  group('MistralBatchTranscriber : audio facturé par appel', () {
    test('réponse réelle de la sonde : 60 s facturées, mêmes morceaux que '
        'transcribe', () async {
      final _Http http = _Http(
        (int _, int _) async => ResponseBody.fromString(
          mistralBatch60Body,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      );
      final MistralBatchTranscriber t = _mistral(http);

      final ({List<({int offsetMs, String text})> pieces, int billedMs}) r =
          await t.transcribeBilled(_voiced(60000));

      expect(r.billedMs, 60000);
      expect(r.pieces, await t.transcribe(_voiced(60000)));
      expect(r.pieces, isNotEmpty);
    });

    test('secondes fractionnaires : arrondies à la ms', () async {
      final MistralBatchTranscriber t = _mistral(
        _Http((int _, int _) async => _ok(seconds: 12.5)),
      );
      expect((await t.transcribeBilled(_voiced(12500))).billedMs, 12500);
    });

    test('sans champ usage : la longueur du PCM envoyé', () async {
      final MistralBatchTranscriber t = _mistral(
        _Http((int _, int _) async => _ok()),
      );
      expect((await t.transcribeBilled(_voiced(5000))).billedMs, 5000);
    });

    test('clé refusée ou serveur injoignable : TranscriberUnavailable, rien '
        'de facturé', () async {
      for (final Future<ResponseBody> Function(int, int) reply
          in <Future<ResponseBody> Function(int, int)>[
            (int _, int _) async => _json(401, <String, Object>{}),
            (int _, int _) async => _json(500, <String, Object>{}),
          ]) {
        await expectLater(
          _mistral(_Http(reply)).transcribeBilled(_voiced(1000)),
          throwsA(isA<TranscriberUnavailable>()),
        );
      }
    });
  });

  group('EngineTranscriber : le moteur du moment décide', () {
    test('moteur local : la réponse locale, rien de facturé, Mistral jamais '
        'appelé', () async {
      final _Http http = _Http((int _, int _) async => _ok(seconds: 9));
      final _Local local = _Local();
      final EngineTranscriber t = EngineTranscriber(
        local: local,
        cloud: _mistral(http),
        engine: () async => TranscriptionEngine.local,
      );

      final ({List<({int offsetMs, String text})> pieces, int billedMs}) r =
          await t.transcribeBilled(_voiced(9000));

      expect(r.billedMs, 0);
      expect(r.pieces, hasLength(1));
      expect(local.calls, 1);
      expect(http.calls, 0);
    });

    test('moteur Mistral : l audio facturé par Mistral', () async {
      final EngineTranscriber t = EngineTranscriber(
        local: _Local(),
        cloud: _mistral(_Http((int _, int _) async => _ok(seconds: 9))),
        engine: () async => TranscriptionEngine.mistral,
      );
      expect((await t.transcribeBilled(_voiced(9000))).billedMs, 9000);
    });
  });

  group('GapBackfillService : le rattrapage en ligne s ajoute à la note', () {
    late Directory dir;
    late InMemorySessionRepository sessions;
    late InMemoryTranscriptRepository transcripts;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_cloud_usage_');
      sessions = InMemorySessionRepository();
      await sessions.create(
        SessionEntity(
          id: _session,
          title: 'Point équipe',
          createdAt: DateTime(2026, 11, 26, 10),
          updatedAt: DateTime(2026, 11, 26, 11),
          status: SessionStatus.completed,
        ),
      );
      transcripts = InMemoryTranscriptRepository();
    });
    tearDown(() => dir.delete(recursive: true));

    /// WAV micro de [seconds] s : parole toutes les 20 s (8 s), silence
    /// ailleurs.
    Future<void> wav(int seconds) async {
      final WavRecorder r = WavRecorder();
      await r.open('${dir.path}/${_session}_mic.wav');
      for (int c = 0; c < seconds * 10; c++) {
        final Uint8List chunk = Uint8List(3200);
        final ByteData d = ByteData.sublistView(chunk);
        final bool talk = (c * 100) % 20000 < 8000;
        for (int i = 0; i < 1600; i++) {
          d.setInt16(
            i * 2,
            talk ? (i.isEven ? 1000 : -1000) : 0,
            Endian.little,
          );
        }
        await r.append(chunk);
      }
      await r.close();
    }

    /// Un repère de perte au micro, de [fromMs] à [toMs] (ms de réunion).
    Future<void> marker(int fromMs, int toMs) => transcripts.save(
      TranscriptSegmentEntity(
        id: '${_session}_input_1',
        sessionId: _session,
        source: AudioSource.input,
        text: LiveTranscriptionService.gapMarkerText(fromMs, toMs),
        timestampMs: fromMs,
        createdAt: DateTime(2026, 11, 26, 10),
      ),
    );

    Future<void> backfill(
      _Http http, {
      TranscriptionEngine engine = TranscriptionEngine.mistral,
      _Local? local,
    }) => GapBackfillService(
      transcriber: EngineTranscriber(
        local: local ?? _Local(),
        cloud: _mistral(http),
        engine: () async => engine,
      ),
      transcripts: transcripts,
      isRecording: () => false,
      sessions: sessions,
    ).backfill(_session, recordingsDirectory: dir.path);

    test('l audio facturé par Mistral (usage de la réponse) est rangé en '
        'batch, rien en temps réel', () async {
      await wav(60);
      await marker(10000, 30000);
      final _Http http = _Http((int _, int _) async => _ok(seconds: 7));

      await backfill(http);

      expect(http.succeeded, greaterThanOrEqualTo(1));
      expect(sessions.cloudUsage[_session]?.batchMs, 7000 * http.succeeded);
      expect(sessions.cloudUsage[_session]?.realtimeMs ?? 0, 0);
    });

    test('sans champ usage : l audio réellement envoyé (données du WAV '
        'reçu)', () async {
      await wav(60);
      await marker(10000, 30000);
      final _Http http = _Http((int _, int _) async => _ok());

      await backfill(http);

      expect(http.receivedMs, greaterThan(0));
      expect(sessions.cloudUsage[_session]?.batchMs, http.receivedMs);
    });

    test('un appel réussi qui ne retrouve rien est facturé aussi', () async {
      await wav(60);
      await marker(10000, 30000);
      final _Http http = _Http(
        (int _, int _) async => _ok(seconds: 4, empty: true),
      );

      await backfill(http);

      expect(http.succeeded, greaterThanOrEqualTo(1));
      expect(sessions.cloudUsage[_session]?.batchMs, 4000 * http.succeeded);
    });

    test('Mistral refuse ou ne répond pas : rien d ajouté', () async {
      await wav(60);
      await marker(10000, 30000);
      for (final int status in <int>[401, 500]) {
        final _Http http = _Http(
          (int _, int _) async => _json(status, <String, Object>{}),
        );
        await backfill(http);
        expect(http.calls, greaterThanOrEqualTo(1), reason: 'HTTP $status');
      }
      expect(sessions.cloudUsage[_session], isNull);
    });

    test('long repère, une tranche réussie puis un refus : seule la tranche '
        'réussie est facturée', () async {
      await wav(260);
      await marker(10000, 250000);
      final _Http http = _Http(
        (int call, int _) async =>
            call == 1 ? _ok(seconds: 50) : _json(401, <String, Object>{}),
      );

      await backfill(http);

      expect(http.calls, greaterThanOrEqualTo(2), reason: 'plusieurs tranches');
      expect(http.succeeded, 1);
      expect(sessions.cloudUsage[_session]?.batchMs, 50000);
    });

    test('moteur local : rien d ajouté', () async {
      await wav(60);
      await marker(10000, 30000);
      final _Http http = _Http((int _, int _) async => _ok(seconds: 7));
      final _Local local = _Local();

      await backfill(http, engine: TranscriptionEngine.local, local: local);

      expect(local.calls, greaterThanOrEqualTo(1));
      expect(http.calls, 0);
      expect(sessions.cloudUsage[_session], isNull);
    });

    test('additif : un rattrapage repris plus tard s ajoute à l usage déjà '
        'rangé (réunion, rattrapage précédent)', () async {
      await wav(60);
      await marker(10000, 30000);
      await sessions.addCloudUsage(
        _session,
        realtimeMs: 600000,
        batchMs: 60000,
      );
      final _Http http = _Http((int _, int _) async => _ok(seconds: 7));

      await backfill(http);

      expect(sessions.cloudUsage[_session]?.realtimeMs, 600000);
      expect(
        sessions.cloudUsage[_session]?.batchMs,
        60000 + 7000 * http.succeeded,
      );
    });
  });
}
