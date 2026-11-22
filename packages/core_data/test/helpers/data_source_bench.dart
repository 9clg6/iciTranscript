import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';

import 'fake_websocket_client.dart';

/// Banc commun du tour 5 : vraie source distante, deux sockets factices,
/// horloge factice. Un seul abonnement par flux (le décodage est fait par
/// abonné).
final class DataSourceBench {
  DataSourceBench(this.async, {bool systemAudio = true})
    : mic = FakeWebSocketClient(now: () => async.elapsed),
      system = FakeWebSocketClient(now: () => async.elapsed) {
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: system,
    );
    dataSource.audioGaps.listen(gaps.add);
    dataSource.transcriptionStream.listen(micEvents.add);
    dataSource.systemTranscriptionStream.listen(systemEvents.add);
    unawaited(dataSource.connect(systemAudioEnabled: systemAudio));
    async.flushMicrotasks();
  }

  static const int t0 = 1700000000000;

  final FakeAsync async;
  final FakeWebSocketClient mic;
  final FakeWebSocketClient system;
  late final TranscriptionRemoteDataSourceImpl dataSource;
  final List<AudioGap> gaps = <AudioGap>[];
  final List<TranscriptEventRemoteModel> micEvents =
      <TranscriptEventRemoteModel>[];
  final List<TranscriptEventRemoteModel> systemEvents =
      <TranscriptEventRemoteModel>[];

  FakeWebSocketClient socketOf(AudioSource source) =>
      source == AudioSource.input ? mic : system;

  /// Un chunk de 100 ms par source listée, puis 100 ms de temps simulé.
  void tick(
    int id, {
    Map<AudioSource, bool> voiced = const <AudioSource, bool>{},
  }) {
    for (final MapEntry<AudioSource, bool> v in voiced.entries) {
      dataSource.sendAudio(
        chunk(v.key, id, timestampMs: t0 + id * 100, voiced: v.value),
      );
    }
    async.elapse(const Duration(milliseconds: 100));
  }

  /// Parole d'une source : 8 s de voix, 2 s de pause, [cycles] fois, à
  /// partir de [fromId]. Rend les ids voisés.
  List<int> speak(AudioSource source, int fromId, int cycles) {
    final List<int> voicedIds = <int>[];
    for (int id = fromId; id < fromId + cycles * 100; id++) {
      final bool v = (id - fromId) % 100 < 80;
      if (v) voicedIds.add(id);
      tick(id, voiced: <AudioSource, bool>{source: v});
    }
    return voicedIds;
  }

  bool inGap(AudioSource source, int id) => gaps.any(
    (AudioGap g) =>
        g.source == source &&
        t0 + id * 100 >= g.startMs &&
        t0 + id * 100 < g.endMs,
  );

  void systemChatter() => system.emit(<String, Object>{
    'type': 'response.audio_transcript.delta',
    'delta': 'bla ',
  });
}
