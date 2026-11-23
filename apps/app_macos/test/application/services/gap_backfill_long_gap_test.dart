import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/gap_backfill_retry.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/recorded_backfill.dart' show markerRange;

// Suivi du tour 10, point 3 — UN LONG TROU FINIT TOUJOURS RATTRAPÉ (fin de
// la sonde 9 : serveur ralenti, 47 puis 36 phrases encore sous un repère à
// la fin, « le rattrapage a atteint sa limite de 5 minutes »).
//
// La limite : `LiveTranscriptionService._backfillLimit` (5 min), un
// `.timeout` autour de `GapBackfillRetry.afterSession` (ou de
// `GapBackfillService.backfill`) à l'arrêt. `GapBackfillService.backfill`
// retranscrit chaque union en UN appel au transcripteur ; le
// transcripteur borne chaque attente de `done` à 60 s ; `GapBackfillRetry`
// compte une tentative dès que le serveur a été atteint, 3 au plus.
//
// Attendu : une tentative peut être bornée dans le temps, mais une
// tentative qui a avancé (au moins un intervalle rendu) ne consomme pas un
// des trois essais, et la suivante reprend là où la précédente s'est
// arrêtée (ce qui est rendu n'est pas retranscrit, le repère rétrécit ou
// se coupe à ce qui reste) ; avec un transcripteur sain, un trou de 8 min
// finit entièrement rattrapé, sans repère, sans relancer l'app ; les trois
// essais ne valent que pour des tentatives qui ont atteint le serveur sans
// rien rendre ; pendant ce temps, la note montre ce qui manque (repère) et
// le fichier d'attente garde la session.
//
// Banc : la borne d'une tentative est jouée par le transcripteur factice,
// sain mais lent (0,4× : 5 min de tentative = 2 min d'audio) : au-delà de
// [_perAttempt] d'audio demandé dans une tentative, l'appel est coupé
// (`TranscriberUnavailable`) et la tentative s'arrête ; la suivante repart
// avec un budget neuf. Il rend les phrases lues dans l'audio demandé.
const String _session = '1700000000000';
const int _gapStartMs = 10000;
const int _gapEndMs = 490000; // 8 min
const Duration _perAttempt = Duration(seconds: 120);

String _sentence(int k) => 'Phrase lue $k, le facteur répare la barrière $k.';
int _sentenceStart(int k) => k * 10000 + 500;
final List<int> _sentences = <int>[
  for (int k = 1; k <= 47; k++) k,
]; // 10,5 s … 477,5 s, 7,5 s chacune

final class _SlowTranscriber implements PcmTranscriber {
  _SlowTranscriber(this.onCut);

  /// Appelé quand une tentative est coupée (état de la note à cet instant).
  final Future<void> Function() onCut;

  int _spentMs = 0;
  Duration perAttempt = _perAttempt;
  int calls = 0;
  int cuts = 0;
  bool returnNothing = false;

  /// Intervalles d'audio (ms) réellement retranscrits.
  final List<(int, int)> transcribed = <(int, int)>[];

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls++;
    final int v = ByteData.sublistView(pcm).getInt16(0, Endian.little);
    final int startMs = (v ~/ 4) * 100;
    final int durationMs = pcm.length ~/ 32;
    if (_spentMs + durationMs > perAttempt.inMilliseconds) {
      _spentMs = 0;
      cuts++;
      await onCut();
      throw const TranscriberUnavailable('borne de la tentative');
    }
    _spentMs += durationMs;
    transcribed.add((startMs, startMs + durationMs));
    if (returnNothing) return const <({int offsetMs, String text})>[];
    return <({int offsetMs, String text})>[
      for (final int k in _sentences)
        if (_sentenceStart(k) >= startMs - 500 &&
            _sentenceStart(k) < startMs + durationMs)
          (offsetMs: _sentenceStart(k) - startMs, text: _sentence(k)),
    ];
  }
}

void main() {
  late Directory dir;
  late InMemoryTranscriptRepository repo;
  late StreamController<ServerState> states;
  late _SlowTranscriber transcriber;
  late List<String> cutProblems;

  File pending() => File('${dir.path}/.backfill_pending.json');

  List<({int startMs, int endMs})> markers() => <({int startMs, int endMs})>[
    for (final TranscriptSegmentEntity s in repo.of(AudioSource.input))
      if (s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix))
        markerRange(s.text)!,
  ];

  String note() => repo
      .of(AudioSource.input)
      .map((TranscriptSegmentEntity s) => s.text)
      .join(' ');

  /// Chaque phrase est dans la note OU sous un repère, jamais les deux ; le
  /// fichier d'attente garde la session.
  Future<void> checkWhileItGoesOn() async {
    final String text = note();
    final List<({int startMs, int endMs})> under = markers();
    for (final int k in _sentences) {
      final bool shown = text.contains('Phrase lue $k,');
      final bool covered = under.any(
        (({int startMs, int endMs}) m) =>
            m.startMs <= _sentenceStart(k) + 1000 &&
            m.endMs + 1000 >= _sentenceStart(k) + 7500,
      );
      if (!shown && !covered) {
        cutProblems.add(
          'coupe ${transcriber.cuts} : $k ni rendue ni sous repère',
        );
      }
      if (shown && covered) {
        cutProblems.add('coupe ${transcriber.cuts} : $k rendue ET sous repère');
      }
    }
    if (!pending().existsSync() ||
        !pending().readAsStringSync().contains(_session)) {
      cutProblems.add('coupe ${transcriber.cuts} : session absente du fichier');
    }
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('oats_long_gap_');
    repo = InMemoryTranscriptRepository();
    states = StreamController<ServerState>.broadcast();
    cutProblems = <String>[];
    transcriber = _SlowTranscriber(checkWhileItGoesOn);
    final WavRecorder recorder = WavRecorder();
    await recorder.open('${dir.path}/${_session}_mic.wav');
    for (int c = 0; c < 5000; c++) {
      final Uint8List chunk = Uint8List(3200);
      final ByteData d = ByteData.sublistView(chunk);
      for (int o = 0; o < 3200; o += 2) {
        d.setInt16(o, c * 4 + 1, Endian.little);
      }
      await recorder.append(chunk);
    }
    await recorder.close();
    await repo.save(
      TranscriptSegmentEntity(
        id: '${_session}_input_1',
        sessionId: _session,
        source: AudioSource.input,
        text: LiveTranscriptionService.gapMarkerText(_gapStartMs, _gapEndMs),
        timestampMs: _gapStartMs,
        createdAt: DateTime(2026, 11, 24),
      ),
    );
  });

  tearDown(() async {
    await states.close();
    await dir.delete(recursive: true);
  });

  GapBackfillRetry launch() => GapBackfillRetry(
    backfill: GapBackfillService(
      transcriber: transcriber,
      transcripts: repo,
      isRecording: () => false,
    ),
    serverStates: states.stream,
    isRecording: () => false,
    recordingsDirectory: dir.path,
  );

  /// Attend que la file des tentatives se calme (temps réel, fichiers).
  Future<void> settle(bool Function() done) async {
    for (int i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('un trou de 8 min finit rattrapé, sans repère, sans relancer l app ni '
      'attendre un autre signal du serveur', () async {
    final GapBackfillRetry retry = launch();
    addTearDown(retry.dispose);
    await retry.afterSession(_session);
    await settle(() => markers().isEmpty);

    expect(markers(), isEmpty, reason: 'coupes : ${transcriber.cuts}');
    final List<int> missing = <int>[
      for (final int k in _sentences)
        if (!note().contains('Phrase lue $k,')) k,
    ];
    expect(missing, isEmpty, reason: 'phrases non rendues');
    expect(pending().existsSync(), isFalse, reason: 'plus rien en attente');
    expect(
      transcriber.cuts,
      greaterThan(GapBackfillRetry.maxAttempts),
      reason:
          'plus de coupes que d essais : seules les tentatives sans rien '
          'rendre comptent',
    );
  });

  test('chaque phrase rendue une seule fois ; l audio rendu n est pas '
      'retranscrit', () async {
    final GapBackfillRetry retry = launch();
    addTearDown(retry.dispose);
    await retry.afterSession(_session);
    await settle(() => markers().isEmpty);

    for (final int k in _sentences) {
      expect(
        'Phrase lue $k,'.allMatches(note()).length,
        lessThanOrEqualTo(1),
        reason: 'phrase $k',
      );
    }
    final int total = transcriber.transcribed.fold<int>(
      0,
      (int sum, (int, int) r) => sum + r.$2 - r.$1,
    );
    expect(
      total,
      lessThan((_gapEndMs - _gapStartMs) * 1.25),
      reason: 'audio retranscrit ${total ~/ 1000} s pour un trou de 480 s',
    );
  });

  test('pendant le rattrapage : la note montre ce qui manque (repère rétréci '
      'ou coupé), le fichier d attente garde la session', () async {
    final GapBackfillRetry retry = launch();
    addTearDown(retry.dispose);
    await retry.afterSession(_session);
    await settle(() => markers().isEmpty);

    expect(transcriber.cuts, greaterThan(0), reason: 'au moins une coupe');
    expect(cutProblems, isEmpty, reason: cutProblems.join('\n'));
  });

  test('garde : des tentatives qui atteignent le serveur sans rien rendre '
      's arrêtent à trois, le repère reste', () async {
    // Sans borne ici : seules comptent les tentatives qui ne rendent rien.
    transcriber
      ..returnNothing = true
      ..perAttempt = const Duration(hours: 1);
    final GapBackfillRetry retry = launch();
    addTearDown(retry.dispose);
    await retry.afterSession(_session);
    for (int i = 0; i < 6; i++) {
      states.add(ServerState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await settle(() => !pending().existsSync());

    expect(markers(), isNotEmpty, reason: 'le repère reste');
    expect(pending().existsSync(), isFalse, reason: 'session abandonnée');
  });
}
