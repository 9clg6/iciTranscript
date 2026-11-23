import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/wav_recorder.dart';

import '../../helpers/live_service_fakes.dart';

// Revue PR #21, chemin réel des doublons (sonde 6, svc_D.jsonl, machine très
// chargée), rejoué tel quel : mêmes textes, même ordre, même retard.
// - 300,08 s : Stop ; l'arrêt attend le rattrapage.
// - 306,3 s / 317,5 s : premiers deltas, en retard, de deux phrases dont
//   l'audio (148,05 s micro ; 138,8 s système) est DANS une perte.
// - 321,45 s : les deux sockets sont remplacées ; pertes déclarées ;
//   `utterance_lost` scelle les deux phrases partielles.
// - 410,8 s : premier delta d'une autre phrase perdue (audio à 223,94 s).
// - 420 s : l'attente atteint 120 s ; le repli de l'arrêt range cette
//   phrase ; la déconnexion déclare la dernière perte.
// Les trois partiels étaient rangés à l'heure d'arrivée de leur premier
// delta (306,3 / 317,5 / 410,8 s), hors de la fenêtre de leur perte ; le
// rattrapage ne les voyait pas et la phrase retrouvée s'y ajoutait.
//
// Attendu :
// a. une phrase partielle scellée parce que sa phrase est perdue est rangée
//    à l'heure où son AUDIO a commencé (début de la perte qui l'emporte),
//    et reste visible tant que le rattrapage ne l'a pas remplacée ;
// b. pareil pour le repli de l'arrêt à 120 s ;
// c. avec le rattrapage, chaque phrase apparaît une seule fois, dans l'ordre.
void main() {
  const String micPartial1 =
      'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, '
      'puis la';
  const String sysPartial =
      'La boulangère a décoré la cabane pendant la fête du village, puis le '
      'libraire';
  const String micPartial2 =
      'La boulangère a repeint la serre pendant la fête du village,';

  // Pertes déclarées (repères de la sonde : début, fin de l'audio perdu).
  const (int, int) micLost1 = (148048, 165000);
  const (int, int) sysLost1 = (138748, 164000);
  const (int, int) micLost2 = (223948, 300000);
  const (int, int) sysLost2 = (212148, 300000);

  void at(FakeAsync async, double seconds) {
    final Duration target = Duration(milliseconds: (seconds * 1000).round());
    if (async.elapsed < target) async.elapse(target - async.elapsed);
  }

  AudioGap gap(LiveServiceHarness h, AudioSource s, (int, int) lost) =>
      AudioGap(source: s, startMs: h.t0 + lost.$1, endMs: h.t0 + lost.$2);

  /// Rejoue svc_D jusqu'à la fin de l'arrêt.
  LiveServiceHarness replay(FakeAsync async, {double until = 430}) {
    final LiveServiceHarness h = LiveServiceHarness(async)..start();
    at(async, 300.08);
    h.fakeRemote
      ..active = <AudioSource>{AudioSource.input, AudioSource.output}
      ..gapsOnDisconnect = <AudioGap>[
        gap(h, AudioSource.input, micLost2),
        gap(h, AudioSource.output, sysLost2),
      ];
    unawaited(h.service.stopTranscription());
    at(async, 306.333);
    h.fakeRemote.emitDelta(AudioSource.input, micPartial1);
    at(async, 317.525);
    h.fakeRemote.emitDelta(AudioSource.output, sysPartial);
    at(async, 321.45);
    h.fakeRemote
      ..emitGap(gap(h, AudioSource.input, micLost1))
      ..emitGap(gap(h, AudioSource.output, sysLost1))
      ..emitControl(AudioSource.input, utteranceLostEventType)
      ..emitControl(AudioSource.output, utteranceLostEventType);
    at(async, 410.803);
    h.fakeRemote.emitDelta(AudioSource.input, micPartial2);
    at(async, until);
    return h;
  }

  TranscriptSegmentEntity saved(LiveServiceHarness h, String text) =>
      h.segments.store.values.singleWhere(
        (TranscriptSegmentEntity s) => s.text == text,
        orElse: () => fail('« $text » n est pas rangé'),
      );

  test('a. les partiels scellés sont rangés à l heure de leur audio et '
      'restent visibles à côté du repère', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = replay(async, until: 325);

      expect(saved(h, micPartial1).timestampMs, closeTo(micLost1.$1, 1000));
      expect(saved(h, sysPartial).timestampMs, closeTo(sysLost1.$1, 1000));
      expect(
        h.segments.store.values.where(
          (TranscriptSegmentEntity s) =>
              s.text.startsWith(LiveTranscriptionService.gapMarkerPrefix) &&
              s.timestampMs == micLost1.$1,
        ),
        hasLength(1),
        reason: 'le repère de la perte est là aussi',
      );

      at(async, 430); // arrêt fini, aucun rattrapage
      expect(saved(h, micPartial1).timestampMs, closeTo(micLost1.$1, 1000));
      expect(saved(h, sysPartial).timestampMs, closeTo(sysLost1.$1, 1000));
    });
  });

  test('b. le repli de l arrêt à 120 s range le partiel à l heure de son '
      'audio', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness h = replay(async);

      expect(saved(h, micPartial2).timestampMs, closeTo(micLost2.$1, 1000));
    });
  });

  test('c. avec le rattrapage, chaque phrase une seule fois, dans l ordre, '
      'les partiels remplacés', () async {
    late LiveServiceHarness h;
    fakeAsync((FakeAsync async) => h = replay(async));
    final String sessionId = h.session.id;

    final Directory dir = await Directory.systemTemp.createTemp(
      'oats_sealed_partial_',
    );
    addTearDown(() => dir.delete(recursive: true));
    for (final (String track, int tag) in <(String, int)>[
      ('mic', 1),
      ('system', 2),
    ]) {
      final WavRecorder recorder = WavRecorder();
      await recorder.open('${dir.path}/${sessionId}_$track.wav');
      for (int c = 0; c < 3200; c++) {
        final Uint8List chunk = Uint8List(3200);
        final ByteData d = ByteData.sublistView(chunk);
        for (int o = 0; o < 3200; o += 2) {
          d.setInt16(o, c * 4 + tag, Endian.little);
        }
        await recorder.append(chunk);
      }
      await recorder.close();
    }

    await GapBackfillService(
      transcriber: _Recorded(),
      transcripts: h.segments,
      isRecording: () => false,
    ).backfill(sessionId, recordingsDirectory: dir.path);

    for (final String partial in <String>[
      micPartial1,
      sysPartial,
      micPartial2,
    ]) {
      expect(
        h.segments.store.values.where(
          (TranscriptSegmentEntity s) => s.text == partial,
        ),
        isEmpty,
        reason: 'partiel remplacé : « $partial »',
      );
    }
    final Map<AudioSource, List<String>> clauses = <AudioSource, List<String>>{
      AudioSource.input: <String>[
        'La boulangère a nettoyé le kiosque à journaux',
        'The baker painted the garden gate',
        'La boulangère a repeint la serre',
      ],
      AudioSource.output: <String>[
        'La boulangère a décoré la cabane',
        'The baker painted the old greenhouse',
      ],
    };
    clauses.forEach((AudioSource source, List<String> ordered) {
      final List<TranscriptSegmentEntity> lines = h.segments.of(source)
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      int last = -1;
      for (final String clause in ordered) {
        final List<int> at = <int>[
          for (int i = 0; i < lines.length; i++)
            if (lines[i].text.contains(clause)) i,
        ];
        expect(at, hasLength(1), reason: '« $clause » une seule fois');
        expect(
          at.single,
          greaterThan(last),
          reason: '« $clause » dans l ordre',
        );
        last = at.single;
      }
    });
  });
}

/// Texte que le vrai serveur a rendu au rattrapage (sonde 6, D), en heures
/// de réunion ; rendu relatif au début du PCM demandé. Chaque échantillon
/// d'un pas de 100 ms vaut numéro × 4 + piste (1 micro, 2 système).
final class _Recorded implements PcmTranscriber {
  static const List<({int atMs, String text})> _pieces =
      <({int atMs, String text})>[
        (
          atMs: 147048,
          text:
              'La boulangère a nettoyé le kiosque à journaux malgré le vent '
              'froid, puis la boulangère a décoré le kiosque à journaux avec '
              'beaucoup de patience.',
        ),
        (
          atMs: 157348,
          text:
              'The baker painted the garden gate for the start of school, and '
              'then the mayor moved the wooden fence before the evening rain.',
        ),
        (
          atMs: 222948,
          text:
              'La boulangère a repeint la serre pendant la fête du village, '
              'puis la gardienne a repeint le kiosque à journaux pendant la '
              'fête du village.',
        ),
      ];
  static const List<({int atMs, String text})> _system =
      <({int atMs, String text})>[
        (
          atMs: 137748,
          text:
              'La boulangère a décoré la cabane pendant la fête du village, '
              'puis le libraire a rangé la fontaine ronde avec beaucoup de '
              'patience.',
        ),
        (
          atMs: 146548,
          text:
              'The baker painted the old greenhouse at sunrise, and then the '
              'librarian painted the small cabin with a lot of patience.',
        ),
      ];

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final int v = ByteData.sublistView(pcm).getInt16(0, Endian.little);
    final int tag = v % 4;
    final int startMs = (v ~/ 4) * 100;
    final int endMs = startMs + pcm.length ~/ 32;
    final List<({int atMs, String text})> all = tag == 1 ? _pieces : _system;
    return <({int offsetMs, String text})>[
      for (final ({int atMs, String text}) p in all)
        if (p.atMs >= startMs - 1500 && p.atMs < endMs)
          (offsetMs: p.atMs - startMs, text: p.text),
    ];
  }
}
