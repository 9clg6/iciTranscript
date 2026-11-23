import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/websocket_pcm_transcriber.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/memory_fs.dart';

// Sonde 13 (banc avec pauses, scénario P2, live13/) : après l'arrêt (borne
// de l'attente à 721 s), le rattrapage d'après réunion a ouvert ses deux
// connexions pendant que le serveur traitait encore l'arriéré de la
// réunion : poignée de main expirée à 10 s, classée « connexion refusée »
// (serveur non atteint : tentative non comptée), puis PLUS RIEN — les
// repères (micro 5:18–10:00, système 1:09–9:59) sont restés 8 min et plus,
// l'app ouverte. Pas une perte (repères + fichier d'attente), mais la
// reprise attendait un relancement.
//
// Attendu :
// 1. une tentative qui n'a pas atteint le serveur (poignée de main expirée
//    ou refus) est reprise d'elle-même tant que l'app tourne et que rien
//    n'enregistre : 15 s, 30 s, 60 s après chaque échec, puis toutes les
//    2 min, sans relancement, jusqu'à atteindre le serveur ; ces tentatives
//    ne comptent pas parmi les trois essais ; un enregistrement qui
//    commence suspend les reprises, elles repartent après lui ;
// 2. la poignée de main du rattrapage suit la même borne adaptative que la
//    reconnexion en direct (10 → 20 → 40 → 60 s) : un serveur occupé qui
//    accepte en 15–30 s est atteint à la tentative suivante au lieu
//    d'échouer à 10 s à chaque fois ;
// 3. serveur occupé les 40 premières secondes après l'arrêt, sain ensuite :
//    la note finit entièrement rattrapée en ~2 min, sans repère, chaque
//    phrase une fois.
//
// Banc : fichiers en mémoire (IOOverrides) pour tout jouer sous fakeAsync.
// Chaque pas de 100 ms du WAV porte son numéro dans ses 4 premiers
// échantillons (valeurs < 64) ; parlé = ±1000 (passe la porte), silence = 0.
const String _session = '1700000000000';
const String _dir = '/mem/recordings';
const List<Duration> _backoff = <Duration>[
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(minutes: 2),
  Duration(minutes: 2),
];

typedef _Sentence = ({int startMs, int endMs, String text});

const List<String> _vocab = <String>[
  'budget',
  'planning',
  'client',
  'serveur',
  'contrat',
  'équipe',
  'livraison',
  'facture',
  'réunion',
  'projet',
  'tableau',
  'priorité',
  'risque',
  'version',
  'maquette',
  'tests',
  'données',
  'rapport',
  'objectif',
  'trimestre',
  'stratégie',
  'formation',
  'recrutement',
  'sécurité',
  'mobile',
  'design',
  'migration',
  'support',
  'marketing',
  'ventes',
  'achats',
  'logistique',
  'qualité',
  'audit',
  'juridique',
  'partenaire',
  'lancement',
  'calendrier',
  'feuille',
  'route',
  'indicateur',
  'bilan',
  'prototype',
  'atelier',
  'fournisseur',
  'stock',
  'inventaire',
  'licence',
  'réseau',
  'serveurs',
  'sauvegarde',
  'archive',
  'messagerie',
  'agenda',
  'dossier',
  'compte',
  'paiement',
  'remise',
  'tarif',
  'devis',
];

/// Phrase toutes les 20 s, 7,5 s chacune, dans [fromMs, toMs) ; deux
/// phrases voisines n'ont aucun mot commun hors du préfixe.
List<_Sentence> _sentences(String who, int fromMs, int toMs) => <_Sentence>[
  for (int at = fromMs + 1000, k = 0; at + 7500 < toMs; at += 20000, k++)
    (
      startMs: at,
      endMs: at + 7500,
      text:
          '$who ${at ~/ 1000} : '
          '${<String>[for (int w = 0; w < 6; w++) _vocab[(k * 6 + w) % _vocab.length]].join(' ')}.',
    ),
];

// P2 : micro 5:18–10:00, système 1:09–9:59.
final List<_Sentence> _mic = _sentences('Micro', 318000, 600000);
final List<_Sentence> _sys = _sentences('Système', 69000, 599000);

List<_Sentence> _of(int tag) => tag == 1 ? _mic : _sys;

Uint8List _track(int tag, int ms) {
  final Uint8List out = Uint8List(ms * 32);
  final ByteData d = ByteData.sublistView(out);
  for (int c = 0; c < ms ~/ 100; c++) {
    final bool talk = _of(
      tag,
    ).any((_Sentence s) => c * 100 >= s.startMs && c * 100 < s.endMs);
    for (int i = 0; i < 1600; i++) {
      final int v = switch (i) {
        0 => c % 64,
        1 => (c ~/ 64) % 64,
        2 => c ~/ 4096,
        3 => tag,
        _ => talk ? (i.isEven ? 1000 : -1000) : 0,
      };
      d.setInt16((c * 1600 + i) * 2, v, Endian.little);
    }
  }
  return out;
}

({int tag, int startMs}) _decode(Uint8List pcm) {
  final ByteData d = ByteData.sublistView(pcm);
  final int c =
      d.getInt16(0, Endian.little) +
      64 * d.getInt16(2, Endian.little) +
      4096 * d.getInt16(4, Endian.little);
  return (tag: d.getInt16(6, Endian.little), startMs: c * 100);
}

/// Phrases entendues dans [pcm] (début dans l'audio demandé).
List<({int offsetMs, String text})> _heard(Uint8List pcm) {
  final ({int tag, int startMs}) at = _decode(pcm);
  final int endMs = at.startMs + pcm.length ~/ 32;
  return <({int offsetMs, String text})>[
    for (final _Sentence s in _of(at.tag))
      if (s.startMs >= at.startMs - 500 && s.startMs < endMs)
        (
          offsetMs: s.startMs - at.startMs < 0 ? 0 : s.startMs - at.startMs,
          text: s.text,
        ),
  ];
}

TranscriptSegmentEntity _marker(String id, AudioSource source, int s, int e) =>
    TranscriptSegmentEntity(
      id: id,
      sessionId: _session,
      source: source,
      text: LiveTranscriptionService.gapMarkerText(s, e),
      timestampMs: s,
      createdAt: DateTime(2026, 11, 25),
    );

/// Base et WAV de la séance P2 (repères seuls).
Future<InMemoryTranscriptRepository> _seed(MemoryFs fs) async {
  fs
    ..wav('$_dir/${_session}_mic.wav', _track(1, 620000))
    ..wav('$_dir/${_session}_system.wav', _track(2, 620000));
  final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
  await repo.save(
    _marker('${_session}_input_1', AudioSource.input, 318000, 600000),
  );
  await repo.save(
    _marker('${_session}_output_2', AudioSource.output, 69000, 599000),
  );
  return repo;
}

bool _isGapMarker(TranscriptSegmentEntity s) =>
    s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix);

/// Transcripteur qui n'atteint pas le serveur avant [reachableAfter]
/// (poignée de main expirée à 10 s), sain ensuite.
final class _Unreachable implements PcmTranscriber {
  _Unreachable(this.async, this.reachableAfter);

  final FakeAsync async;
  Duration reachableAfter;
  final List<Duration> calls = <Duration>[];

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls.add(async.elapsed);
    if (async.elapsed < reachableAfter) {
      await Future<void>.delayed(const Duration(seconds: 10));
      throw const TranscriberUnavailable(
        'connexion refusée (TimeoutException after 0:00:10)',
      );
    }
    return _heard(pcm);
  }
}

/// Serveur occupé : la poignée de main aboutit à max(maintenant +
/// [acceptDelay], [busyUntil]) ; au-delà de `handshakeTimeout` du client,
/// elle expire (comme `WebSocketClient`). Un commit est rendu en 1 s.
final class _BusyServer {
  _BusyServer(this.async);

  final FakeAsync async;
  Duration busyUntil = Duration.zero;
  Duration acceptDelay = Duration.zero;
  final List<Duration> bounds = <Duration>[];
  int connected = 0;

  WebSocketClient client() => _BusySocket(this);
}

final class _BusySocket extends WebSocketClient {
  _BusySocket(this._server);

  final _BusyServer _server;
  bool _connected = false;
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final BytesBuilder _piece = BytesBuilder();

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    _server.bounds.add(handshakeTimeout);
    final Duration now = _server.async.elapsed;
    Duration acceptAt = now + _server.acceptDelay;
    if (_server.busyUntil > acceptAt) acceptAt = _server.busyUntil;
    if (acceptAt - now > handshakeTimeout) {
      await Future<void>.delayed(handshakeTimeout);
      throw TimeoutException('poignée de main', handshakeTimeout);
    }
    await Future<void>.delayed(acceptAt - now);
    _connected = true;
    _server.connected++;
  }

  @override
  void send(String message) {
    if (!_connected) return;
    final Map<String, dynamic> json =
        jsonDecode(message) as Map<String, dynamic>;
    if (json['type'] == 'input_audio_buffer.append') {
      _piece.add(base64Decode(json['audio'] as String));
    } else if (json['type'] == 'input_audio_buffer.commit') {
      final Uint8List pcm = _piece.takeBytes();
      final String text = _heard(
        pcm,
      ).map((({int offsetMs, String text}) p) => p.text).join(' ');
      Timer(const Duration(seconds: 1), () {
        if (!_connected) return;
        _messages.add(
          jsonEncode(<String, Object>{
            'type': 'response.audio_transcript.done',
            'text': text,
          }),
        );
      });
    }
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> dispose() async => _connected = false;
}

/// Tentatives (début, fin) : les appels d'une tentative s'enchaînent, chacun
/// commence à l'échec du précédent (10 s plus tard) ; un écart plus long
/// ouvre une nouvelle tentative.
List<(Duration, Duration)> _attempts(_Unreachable t) {
  final List<(Duration, Duration)> out = <(Duration, Duration)>[];
  for (final Duration call in t.calls) {
    if (out.isNotEmpty &&
        call - out.last.$2 <= const Duration(milliseconds: 500)) {
      out.last = (out.last.$1, call + const Duration(seconds: 10));
    } else {
      out.add((call, call + const Duration(seconds: 10)));
    }
  }
  return out;
}

void main() {
  group('1. reprises automatiques d une tentative qui n a pas atteint le '
      'serveur', () {
    test('reprise 15 s, 30 s, 60 s après chaque échec, puis toutes les '
        '2 min, sans relancement ni signal du serveur', () {
      final MemoryFs fs = MemoryFs();
      fs.run(() {
        fakeAsync((FakeAsync async) {
          final _Unreachable transcriber = _Unreachable(
            async,
            const Duration(hours: 1),
          );
          late InMemoryTranscriptRepository repo;
          _seed(fs).then((InMemoryTranscriptRepository r) => repo = r);
          async.flushMicrotasks();
          final GapBackfillRetry retry = GapBackfillRetry(
            backfill: GapBackfillService(
              transcriber: transcriber,
              transcripts: repo,
              isRecording: () => false,
            ),
            serverStates: const Stream<ServerState>.empty(),
            isRecording: () => false,
            recordingsDirectory: _dir,
          );
          unawaited(retry.afterSession(_session));
          async.elapse(const Duration(minutes: 9));

          final List<(Duration, Duration)> tries = _attempts(transcriber);
          final List<Duration> waits = <Duration>[
            for (int i = 1; i < tries.length; i++)
              tries[i].$1 - tries[i - 1].$2,
          ];
          expect(
            tries.length,
            greaterThanOrEqualTo(_backoff.length + 1),
            reason: 'appels à ${transcriber.calls}',
          );
          for (int i = 0; i < _backoff.length; i++) {
            expect(
              (waits[i] - _backoff[i]).inMilliseconds.abs(),
              lessThanOrEqualTo(2000),
              reason:
                  'reprise ${i + 1} : ${waits[i]} au lieu de ${_backoff[i]}',
            );
          }
          expect(
            utf8.decode(fs.files['$_dir/.backfill_pending.json']!),
            contains('"$_session":0'),
            reason: 'en attente, aucune tentative comptée',
          );
        });
      });
    });

    test('le serveur atteint après 8 min d échecs : tout est rattrapé sans '
        'relancement, les échecs n ont pas usé les trois essais', () {
      final MemoryFs fs = MemoryFs();
      fs.run(() {
        fakeAsync((FakeAsync async) {
          final _Unreachable transcriber = _Unreachable(
            async,
            const Duration(minutes: 8),
          );
          late InMemoryTranscriptRepository repo;
          _seed(fs).then((InMemoryTranscriptRepository r) => repo = r);
          async.flushMicrotasks();
          final GapBackfillRetry retry = GapBackfillRetry(
            backfill: GapBackfillService(
              transcriber: transcriber,
              transcripts: repo,
              isRecording: () => false,
            ),
            serverStates: const Stream<ServerState>.empty(),
            isRecording: () => false,
            recordingsDirectory: _dir,
          );
          unawaited(retry.afterSession(_session));
          async.elapse(const Duration(minutes: 12));

          expect(
            _attempts(transcriber)
                .where(
                  ((Duration, Duration) t) => t.$1 < const Duration(minutes: 8),
                )
                .length,
            greaterThan(GapBackfillRetry.maxAttempts),
            reason: 'appels à ${transcriber.calls}',
          );
          expect(repo.store.values.where(_isGapMarker), isEmpty);
          expect(fs.files.containsKey('$_dir/.backfill_pending.json'), isFalse);
        });
      });
    });

    test(
      'un enregistrement suspend les reprises, elles repartent après lui',
      () {
        final MemoryFs fs = MemoryFs();
        fs.run(() {
          fakeAsync((FakeAsync async) {
            final _Unreachable transcriber = _Unreachable(
              async,
              const Duration(minutes: 4),
            );
            bool recording = false;
            late InMemoryTranscriptRepository repo;
            _seed(fs).then((InMemoryTranscriptRepository r) => repo = r);
            async.flushMicrotasks();
            final GapBackfillRetry retry = GapBackfillRetry(
              backfill: GapBackfillService(
                transcriber: transcriber,
                transcripts: repo,
                isRecording: () => recording,
              ),
              serverStates: const Stream<ServerState>.empty(),
              isRecording: () => recording,
              recordingsDirectory: _dir,
            );
            unawaited(retry.afterSession(_session));
            async.elapse(const Duration(seconds: 30));
            recording = true;
            final int before = transcriber.calls.length;
            async.elapse(const Duration(minutes: 5, seconds: 30)); // → 6 min
            expect(
              transcriber.calls.length,
              before,
              reason: 'aucun appel pendant l enregistrement',
            );
            recording = false;
            async.elapse(const Duration(minutes: 4)); // → 10 min
            expect(
              transcriber.calls.where(
                (Duration t) => t >= const Duration(minutes: 6),
              ),
              isNotEmpty,
              reason: 'les reprises repartent après l enregistrement',
            );
            expect(repo.store.values.where(_isGapMarker), isEmpty);
            expect(
              fs.files.containsKey('$_dir/.backfill_pending.json'),
              isFalse,
            );
          });
        });
      },
    );
  });

  group('2. borne adaptative de la poignée de main du rattrapage', () {
    for (final (Duration accept, List<Duration> expected)
        in <(Duration, List<Duration>)>[
          (
            const Duration(seconds: 15),
            <Duration>[Duration(seconds: 10), Duration(seconds: 20)],
          ),
          (
            const Duration(seconds: 30),
            <Duration>[
              Duration(seconds: 10),
              Duration(seconds: 20),
              Duration(seconds: 40),
            ],
          ),
          (
            const Duration(seconds: 100),
            <Duration>[
              Duration(seconds: 10),
              Duration(seconds: 20),
              Duration(seconds: 40),
              Duration(seconds: 60),
              Duration(seconds: 60),
            ],
          ),
        ]) {
      test('un serveur qui accepte en ${accept.inSeconds} s : bornes '
          '${expected.map((Duration d) => d.inSeconds).join(' → ')} s', () {
        fakeAsync((FakeAsync async) {
          final _BusyServer server = _BusyServer(async)..acceptDelay = accept;
          final WebSocketPcmTranscriber transcriber = WebSocketPcmTranscriber(
            url: 'ws://127.0.0.1:1/v1/realtime',
            createClient: server.client,
          );
          // Tentatives successives (le rattrapage réessaie) : le même
          // transcripteur, comme dans l'app.
          for (int i = 0; i < expected.length && server.connected == 0; i++) {
            transcriber
                .transcribe(_track(1, 5000))
                .catchError(
                  (Object _) => const <({int offsetMs, String text})>[],
                );
            async.elapse(const Duration(minutes: 2));
          }
          expect(
            server.bounds.take(expected.length).toList(),
            expected,
            reason: 'bornes vues : ${server.bounds}',
          );
          if (accept <= const Duration(seconds: 60)) {
            expect(server.connected, 1, reason: 'serveur atteint');
          }
        });
      });
    }
  });

  test('3. serveur occupé 40 s après l arrêt puis sain : note entièrement '
      'rattrapée en ~2 min, sans repère, chaque phrase une fois', () {
    final MemoryFs fs = MemoryFs();
    fs.run(() {
      fakeAsync((FakeAsync async) {
        final _BusyServer server = _BusyServer(async)
          ..busyUntil = const Duration(seconds: 40);
        late InMemoryTranscriptRepository repo;
        _seed(fs).then((InMemoryTranscriptRepository r) => repo = r);
        async.flushMicrotasks();
        final GapBackfillRetry retry = GapBackfillRetry(
          backfill: GapBackfillService(
            transcriber: WebSocketPcmTranscriber(
              url: 'ws://127.0.0.1:1/v1/realtime',
              createClient: server.client,
            ),
            transcripts: repo,
            isRecording: () => false,
          ),
          serverStates: const Stream<ServerState>.empty(),
          isRecording: () => false,
          recordingsDirectory: _dir,
        );
        unawaited(retry.afterSession(_session));
        async.elapse(const Duration(seconds: 150));

        final List<TranscriptSegmentEntity> lines = repo.store.values.toList();
        expect(
          lines.where(_isGapMarker).map((s) => s.text).toList(),
          isEmpty,
          reason: 'bornes vues : ${server.bounds}',
        );
        final String note = lines
            .map((TranscriptSegmentEntity s) => s.text)
            .join(' ');
        for (final _Sentence s in <_Sentence>[..._mic, ..._sys]) {
          expect(s.text.allMatches(note).length, 1, reason: s.text);
        }
        expect(fs.files.containsKey('$_dir/.backfill_pending.json'), isFalse);
      });
    });
  });

  test('garde du banc : serveur sain dès l arrêt, tout est rattrapé, sans '
      'repère, chaque phrase une fois', () {
    final MemoryFs fs = MemoryFs();
    fs.run(() {
      fakeAsync((FakeAsync async) {
        final _BusyServer server = _BusyServer(async)
          ..busyUntil = Duration.zero;
        late InMemoryTranscriptRepository repo;
        _seed(fs).then((InMemoryTranscriptRepository r) => repo = r);
        async.flushMicrotasks();
        final GapBackfillRetry retry = GapBackfillRetry(
          backfill: GapBackfillService(
            transcriber: WebSocketPcmTranscriber(
              url: 'ws://127.0.0.1:1/v1/realtime',
              createClient: server.client,
            ),
            transcripts: repo,
            isRecording: () => false,
          ),
          serverStates: const Stream<ServerState>.empty(),
          isRecording: () => false,
          recordingsDirectory: _dir,
        );
        unawaited(retry.afterSession(_session));
        async.elapse(const Duration(seconds: 150));

        final List<TranscriptSegmentEntity> lines = repo.store.values.toList();
        expect(
          lines.where(_isGapMarker).map((s) => s.text).toList(),
          isEmpty,
          reason: 'bornes vues : ${server.bounds}',
        );
        final String note = lines
            .map((TranscriptSegmentEntity s) => s.text)
            .join(' ');
        for (final _Sentence s in <_Sentence>[..._mic, ..._sys]) {
          expect(s.text.allMatches(note).length, 1, reason: s.text);
        }
        expect(fs.files.containsKey('$_dir/.backfill_pending.json'), isFalse);
      });
    });
  });
}
