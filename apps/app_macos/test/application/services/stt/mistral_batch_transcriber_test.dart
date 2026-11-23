import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/stt/mistral_batch_transcriber.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../../helpers/live_service_fakes.dart';

// Rattrapage (et dictée) par l'API Mistral « batch » quand le moteur en
// ligne est choisi : WAV 16 kHz mono envoyé en multipart à
// `POST https://api.mistral.ai/v1/audio/transcriptions`, segments horodatés
// rendus en morceaux du `PcmTranscriber` ; ce qui est rattrapé passe par
// les MÊMES portes (porte de parole, règle des doublons, repère qui
// rétrécit).
//
// API supposée (lib/application/services/stt/mistral_batch_transcriber.dart) :
// `MistralBatchTranscriber({required Dio dio, required Future<String?>
// Function() apiKey}) implements PcmTranscriber` ; `static const String
// model` (batch : un modèle listé par le compte, `voxtral-mini-transcribe-
// 3-0` ou `voxtral-mini-latest`) ; `static const String endpoint`.
// Requête : en-tête `Authorization: Bearer` + clé ; champs `model`,
// `timestamp_granularities` = `segment` (incompatible avec `language` :
// pas de `language`), `file` = WAV RIFF PCM16 16 kHz mono. Réponse
// `{text, segments: [{text, start, end}]}` → morceaux (`offsetMs` = start
// × 1000). Clé refusée (401) ou serveur injoignable →
// `TranscriberUnavailable` (tentative non comptée, reprise plus tard) ;
// pas de clé → aucune requête.
const String _key = 'mistral-test-SECRET-0123456789';

/// Transport HTTP factice : garde les requêtes (octets bruts du multipart)
/// et répond par [reply].
final class _Http implements HttpClientAdapter {
  _Http(this.reply);

  Future<ResponseBody> Function(RequestOptions o, Uint8List body) reply;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Uint8List> bodies = <Uint8List>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Uint8List body = requestStream == null
        ? Uint8List(0)
        : Uint8List.fromList(
            await requestStream.expand((Uint8List c) => c).toList(),
          );
    requests.add(options);
    bodies.add(body);
    return reply(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

/// Valeur d'un champ texte du multipart [body].
String? _field(Uint8List body, String name) {
  final String s = latin1.decode(body);
  final RegExpMatch? m = RegExp(
    'name="$name"\\r\\n(?:[^\\r\\n]*\\r\\n)*?\\r\\n([^\\r\\n]*)\\r\\n',
  ).firstMatch(s);
  return m?.group(1);
}

/// En-tête WAV du fichier envoyé.
({int channels, int rate, int bits, int dataBytes})? _wav(Uint8List body) {
  final int at = latin1.decode(body).indexOf('RIFF');
  if (at < 0) return null;
  final ByteData d = ByteData.sublistView(body, at);
  return (
    channels: d.getUint16(22, Endian.little),
    rate: d.getUint32(24, Endian.little),
    bits: d.getUint16(34, Endian.little),
    dataBytes: d.getUint32(40, Endian.little),
  );
}

Uint8List _voiced(int ms) {
  final Uint8List out = Uint8List(ms * 32);
  final ByteData d = ByteData.sublistView(out);
  for (int o = 0; o < out.length; o += 2) {
    d.setInt16(o, (o ~/ 2).isEven ? 1000 : -1000, Endian.little);
  }
  return out;
}

String? _header(RequestOptions o, String name) {
  for (final MapEntry<String, dynamic> e in o.headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return '${e.value}';
  }
  return null;
}

void main() {
  group('requête et réponse', () {
    late _Http http;
    late MistralBatchTranscriber transcriber;

    setUp(() {
      http = _Http(
        (RequestOptions o, Uint8List b) async => _json(200, <String, Object>{
          'text': 'Bonjour à tous. On commence.',
          'segments': <Map<String, Object>>[
            <String, Object>{
              'text': ' Bonjour à tous.',
              'start': 0.4,
              'end': 1.9,
            },
            <String, Object>{
              'text': ' On commence.',
              'start': 3.25,
              'end': 4.1,
            },
          ],
        }),
      );
      transcriber = MistralBatchTranscriber(
        dio: Dio()..httpClientAdapter = http,
        apiKey: () async => _key,
      );
    });

    test('POST multipart vers l API batch, clé en Bearer, modèle constant, '
        'segments horodatés, sans langue', () async {
      await transcriber.transcribe(_voiced(5000));
      final RequestOptions o = http.requests.single;
      expect(o.method, 'POST');
      expect(
        o.uri.toString(),
        'https://api.mistral.ai/v1/audio/transcriptions',
      );
      expect(MistralBatchTranscriber.endpoint, o.uri.toString());
      expect(_header(o, 'authorization'), 'Bearer $_key');
      expect(_header(o, 'content-type'), startsWith('multipart/form-data'));
      final Uint8List body = http.bodies.single;
      expect(_field(body, 'model'), MistralBatchTranscriber.model);
      expect(<String>[
        'voxtral-mini-transcribe-3-0',
        'voxtral-mini-latest',
      ], contains(MistralBatchTranscriber.model));
      expect(_field(body, 'timestamp_granularities'), 'segment');
      expect(_field(body, 'language'), isNull);
    });

    test(
      'le fichier est un WAV PCM16 16 kHz mono, tout l audio demandé',
      () async {
        await transcriber.transcribe(_voiced(5000));
        expect(latin1.decode(http.bodies.single), contains('filename="'));
        expect(latin1.decode(http.bodies.single), contains('.wav"'));
        expect(_wav(http.bodies.single), (
          channels: 1,
          rate: 16000,
          bits: 16,
          dataBytes: 5000 * 32,
        ));
      },
    );

    test('segments → morceaux à leur heure, texte nettoyé', () async {
      expect(
        await transcriber.transcribe(_voiced(5000)),
        <({int offsetMs, String text})>[
          (offsetMs: 400, text: 'Bonjour à tous.'),
          (offsetMs: 3250, text: 'On commence.'),
        ],
      );
    });

    test(
      'clé refusée (401) : TranscriberUnavailable « clé refusée »',
      () async {
        http.reply = (RequestOptions o, Uint8List b) async =>
            _json(401, <String, Object>{'message': 'Unauthorized'});
        await expectLater(
          transcriber.transcribe(_voiced(1000)),
          throwsA(
            isA<TranscriberUnavailable>().having(
              (TranscriberUnavailable e) => '$e',
              'message',
              contains('clé refusée'),
            ),
          ),
        );
      },
    );

    test('serveur injoignable : TranscriberUnavailable', () async {
      http.reply = (RequestOptions o, Uint8List b) async =>
          throw DioException.connectionError(
            requestOptions: o,
            reason: 'injoignable',
          );
      await expectLater(
        transcriber.transcribe(_voiced(1000)),
        throwsA(isA<TranscriberUnavailable>()),
      );
    });

    test('sans clé : aucune requête', () async {
      final MistralBatchTranscriber noKey = MistralBatchTranscriber(
        dio: Dio()..httpClientAdapter = http,
        apiKey: () async => null,
      );
      await expectLater(
        noKey.transcribe(_voiced(1000)),
        throwsA(isA<TranscriberUnavailable>()),
      );
      expect(http.requests, isEmpty);
    });

    test('la clé n apparaît jamais dans les journaux', () async {
      final Directory dir = await Directory.systemTemp.createTemp('oats_log_');
      final String path = '${dir.path}/oats.log';
      Log.writeToFile(path);
      http.reply = (RequestOptions o, Uint8List b) async =>
          _json(401, <String, Object>{
            'message': 'Unauthorized: ${_header(o, 'authorization')}',
          });
      await transcriber
          .transcribe(_voiced(1000))
          .catchError((Object _) => const <({int offsetMs, String text})>[]);
      http.reply = (RequestOptions o, Uint8List b) async =>
          throw DioException.connectionError(
            requestOptions: o,
            reason: 'headers ${o.headers}',
          );
      await transcriber
          .transcribe(_voiced(1000))
          .catchError((Object _) => const <({int offsetMs, String text})>[]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final String log = File(path).existsSync()
          ? File(path).readAsStringSync()
          : '';
      await dir.delete(recursive: true);
      expect(log.contains(_key), isFalse);
    });
  });

  group('rattrapage par Mistral : mêmes portes', () {
    const String session = '1700000000000';
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('oats_mistral_backfill_');
    });
    tearDown(() => dir.delete(recursive: true));

    /// WAV micro de 4 min : parole 20–28 s, 120–128 s, 220–228 s ; silence
    /// ailleurs. Chaque pas de 100 ms porte son numéro (4 premiers
    /// échantillons < 64).
    Future<void> wav() async {
      final WavRecorder r = WavRecorder();
      await r.open('${dir.path}/${session}_mic.wav');
      for (int c = 0; c < 2600; c++) {
        final Uint8List chunk = Uint8List(3200);
        final ByteData d = ByteData.sublistView(chunk);
        final int ms = c * 100;
        final bool talk = <int>[
          20000,
          120000,
          220000,
        ].any((int s) => ms >= s && ms < s + 8000);
        for (int i = 0; i < 1600; i++) {
          final int v = switch (i) {
            0 => c % 64,
            1 => (c ~/ 64) % 64,
            2 => c ~/ 4096,
            _ => talk ? (i.isEven ? 1000 : -1000) : 0,
          };
          d.setInt16(i * 2, v, Endian.little);
        }
        await r.append(chunk);
      }
      await r.close();
    }

    /// Le faux Mistral rend, pour le WAV reçu, les phrases qui y commencent
    /// et « Merci. » au milieu de chaque silence de 30 s (hallucination).
    Future<ResponseBody> mistral(RequestOptions o, Uint8List body) async {
      final int at = latin1.decode(body).indexOf('RIFF');
      final ByteData d = ByteData.sublistView(body, at + 44);
      final int startMs =
          (d.getInt16(0, Endian.little) +
              64 * d.getInt16(2, Endian.little) +
              4096 * d.getInt16(4, Endian.little)) *
          100;
      final int lengthMs =
          ByteData.sublistView(body, at).getUint32(40, Endian.little) ~/ 32;
      final List<Map<String, Object>> segments = <Map<String, Object>>[];
      for (int ms = startMs; ms < startMs + lengthMs; ms += 1000) {
        if (<int>[20000, 120000, 220000].contains(ms)) {
          segments.add(<String, Object>{
            'text': ' Point ${ms ~/ 1000} : budget validé par équipe.',
            'start': (ms - startMs) / 1000,
            'end': (ms - startMs + 8000) / 1000,
          });
        } else if (ms % 50000 == 0) {
          segments.add(<String, Object>{
            'text': ' Merci.',
            'start': (ms - startMs) / 1000,
            'end': (ms - startMs + 1000) / 1000,
          });
        }
      }
      return _json(200, <String, Object>{'text': '', 'segments': segments});
    }

    test('chaque phrase rendue une fois, aucune hallucination rangée sur le '
        'silence, plus de repère', () async {
      await wav();
      final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
      await repo.save(
        TranscriptSegmentEntity(
          id: '${session}_input_1',
          sessionId: session,
          source: AudioSource.input,
          text: LiveTranscriptionService.gapMarkerText(10000, 250000),
          timestampMs: 10000,
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      await GapBackfillService(
        transcriber: MistralBatchTranscriber(
          dio: Dio()..httpClientAdapter = _Http(mistral),
          apiKey: () async => _key,
        ),
        transcripts: repo,
        isRecording: () => false,
      ).backfill(session, recordingsDirectory: dir.path);

      final String note = repo
          .of(AudioSource.input)
          .map((TranscriptSegmentEntity s) => s.text)
          .join(' | ');
      for (final int s in <int>[20, 120, 220]) {
        expect('Point $s :'.allMatches(note).length, 1, reason: note);
      }
      expect(note, isNot(contains('Merci.')));
      expect(note, isNot(contains(LiveTranscriptionService.gapMarkerPrefix)));
    });

    test('une tranche refusée en cours de route : le repère rétrécit à ce qui '
        'reste, rien de rendu n est perdu', () async {
      await wav();
      final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
      await repo.save(
        TranscriptSegmentEntity(
          id: '${session}_input_1',
          sessionId: session,
          source: AudioSource.input,
          text: LiveTranscriptionService.gapMarkerText(10000, 250000),
          timestampMs: 10000,
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      int calls = 0;
      await GapBackfillService(
        transcriber: MistralBatchTranscriber(
          dio: Dio()
            ..httpClientAdapter = _Http((RequestOptions o, Uint8List b) async {
              if (++calls >= 2) return _json(401, <String, Object>{});
              return mistral(o, b);
            }),
          apiKey: () async => _key,
        ),
        transcripts: repo,
        isRecording: () => false,
      ).backfill(session, recordingsDirectory: dir.path);

      final List<TranscriptSegmentEntity> lines = repo.of(AudioSource.input);
      expect(
        lines.map((TranscriptSegmentEntity s) => s.text).join(' '),
        contains('Point 20 :'),
      );
      final List<TranscriptSegmentEntity> markers = lines
          .where(
            (TranscriptSegmentEntity s) =>
                s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix),
          )
          .toList();
      expect(markers, hasLength(1));
      expect(markers.single.timestampMs, greaterThan(28000));
    });
  });
}
