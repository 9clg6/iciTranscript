import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';

import '../../helpers/live_service_fakes.dart';
import '../../helpers/memory_fs.dart';

// Revue de oats-wav-pause (2026-11-25) : un WAV plus court que l'intervalle
// d'un repère de perte (le WAV s'est arrêté, disque plein par exemple) fait
// lever `_readPcm` (`gap_backfill.service.dart:914`, borne basse du clamp
// au-delà de la longueur du fichier). Tout le rattrapage de la session
// tombe alors, repères suivants compris.
//
// Session : WAV micro de 15 s, WAV système de 60 s ; repères micro 3–6 s
// (dans le WAV) et 30–35 s (après sa fin), repère système 40–45 s.
// Transcripteur factice : « Micro N s. » / « Système N s. » pour l'audio
// parlé capté à N s (numéro du chunk dans ses deux premiers échantillons).
//
// Attendu : le rattrapage ne plante pas ; les repères 3–6 s et 40–45 s sont
// remplacés par leur parole ; le repère 30–35 s RESTE dans la note, tel
// quel, sans texte inventé à sa place.
const String _session = '1700000000000';
const String _dir = '/recordings';
const int _systemBase = 10000;

Uint8List _pcm(int chunks, {int base = 0}) {
  final BytesBuilder out = BytesBuilder(copy: false);
  for (int c = 0; c < chunks; c++) {
    out.add(chunk(AudioSource.input, base + c, timestampMs: c * 100).data);
  }
  return out.toBytes();
}

final class _Listener implements PcmTranscriber {
  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    final List<({int offsetMs, String text})> out =
        <({int offsetMs, String text})>[];
    for (int c = 0; (c + 1) * 3200 <= pcm.length; c++) {
      final Uint8List piece = Uint8List.sublistView(
        pcm,
        c * 3200,
        (c + 1) * 3200,
      );
      if (!TranscriptionRemoteDataSourceImpl.isSpeechChunk(piece)) continue;
      final ByteData d = ByteData.sublistView(piece);
      final int id =
          d.getInt16(0, Endian.little) + (d.getInt16(2, Endian.little) << 15);
      final bool system = id >= _systemBase;
      final int at = system ? id - _systemBase : id;
      if (at % 10 == 0) {
        out.add((
          offsetMs: c * 100,
          text: '${system ? 'Système' : 'Micro'} ${at ~/ 10} s.',
        ));
      }
    }
    return out;
  }
}

TranscriptSegmentEntity _marker(
  String id,
  AudioSource source,
  int startMs,
  int endMs,
) => TranscriptSegmentEntity(
  id: id,
  sessionId: _session,
  source: source,
  text: LiveTranscriptionService.gapMarkerText(startMs, endMs),
  timestampMs: startMs,
  createdAt: DateTime(2026, 11, 25),
);

void main() {
  test('un repère au-delà de la fin du WAV : le rattrapage ne plante pas, '
      'les autres repères sont rattrapés, celui-ci reste tel quel', () async {
    final MemoryFs fs = MemoryFs()
      ..wav('$_dir/${_session}_mic.wav', _pcm(150))
      ..wav('$_dir/${_session}_system.wav', _pcm(600, base: _systemBase));
    final InMemoryTranscriptRepository repo = InMemoryTranscriptRepository();
    final TranscriptSegmentEntity early = _marker(
      'm_early',
      AudioSource.input,
      3000,
      6000,
    );
    final TranscriptSegmentEntity pastEnd = _marker(
      'm_past_end',
      AudioSource.input,
      30000,
      35000,
    );
    final TranscriptSegmentEntity system = _marker(
      's_late',
      AudioSource.output,
      40000,
      45000,
    );
    for (final TranscriptSegmentEntity s in <TranscriptSegmentEntity>[
      early,
      pastEnd,
      system,
    ]) {
      await repo.save(s);
    }

    Object? error;
    try {
      await fs.run(
        () => GapBackfillService(
          transcriber: _Listener(),
          transcripts: repo,
          isRecording: () => false,
        ).backfill(_session, recordingsDirectory: _dir),
      );
    } catch (e) {
      error = e;
    }

    final List<TranscriptSegmentEntity> lines = repo.store.values.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final String note = lines
        .map((TranscriptSegmentEntity s) => '${s.timestampMs} ${s.text}')
        .join(' | ');
    final String why =
        'note « $note »${error == null ? '' : ' ; erreur : $error'}';

    expect(error, isNull, reason: why);
    expect(
      note,
      allOf(contains('Micro 4 s.'), contains('Système 41 s.')),
      reason: 'les repères dans l audio sont rattrapés ; $why',
    );
    expect(repo.store['m_early'], isNull, reason: why);
    expect(repo.store['s_late'], isNull, reason: why);
    expect(
      repo.store['m_past_end']?.text,
      pastEnd.text,
      reason: 'le repère sans audio reste, tel quel ; $why',
    );
    expect(
      lines.where(
        (TranscriptSegmentEntity s) =>
            s.source == AudioSource.input &&
            s.id != 'm_past_end' &&
            s.timestampMs >= 15000,
      ),
      isEmpty,
      reason: 'aucun texte inventé après la fin du WAV micro ; $why',
    );
  });
}
