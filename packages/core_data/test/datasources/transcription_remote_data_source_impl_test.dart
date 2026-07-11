import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:test/test.dart';

void main() {
  late _FakeWebSocketClient mic;
  late _FakeWebSocketClient system;
  late TranscriptionRemoteDataSourceImpl dataSource;

  setUp(() {
    mic = _FakeWebSocketClient();
    system = _FakeWebSocketClient();
    dataSource = TranscriptionRemoteDataSourceImpl(
      micClient: mic,
      systemClient: system,
    );
  });

  tearDown(() => dataSource.dispose());

  test(
    'n ouvre pas la WebSocket système quand la capture est désactivée',
    () async {
      await dataSource.connect(systemAudioEnabled: false);

      expect(mic.connectCalls, 1);
      expect(system.connectCalls, 0);
      expect(system.isConnected, isFalse);
    },
  );

  test('route chaque source vers sa propre WebSocket', () async {
    await dataSource.connect();

    dataSource.sendAudio(_chunk(AudioSource.input, 1000, voiced: true));
    dataSource.sendAudio(_chunk(AudioSource.output, 1000, voiced: true));

    expect(_messageTypes(mic.sent), <String>['input_audio_buffer.append']);
    expect(_messageTypes(system.sent), <String>['input_audio_buffer.append']);
  });

  test(
    'une pause finalise et réinitialise uniquement la source active',
    () async {
      await dataSource.connect();
      final StreamSubscription<Object?> subscription = dataSource
          .transcriptionStream
          .listen((_) {});

      dataSource.sendAudio(_chunk(AudioSource.input, 1000, voiced: true));
      dataSource.sendAudio(_chunk(AudioSource.input, 1500, voiced: false));
      dataSource.sendAudio(_chunk(AudioSource.input, 1801, voiced: false));

      expect(_messageTypes(mic.sent), <String>[
        'input_audio_buffer.append',
        'input_audio_buffer.append',
        'input_audio_buffer.commit',
      ]);
      expect(jsonDecode(mic.sent.last), containsPair('final', true));
      expect(dataSource.activeSources, <AudioSource>{AudioSource.input});
      mic.emit(<String, Object>{
        'type': 'response.audio_transcript.done',
        'text': 'bonjour',
      });
      await Future<void>.delayed(Duration.zero);
      expect(dataSource.activeSources, isEmpty);
      expect(system.sent, isEmpty);
      await subscription.cancel();
    },
  );

  test('borne à 30 secondes une session sans silence', () async {
    await dataSource.connect();
    final StreamSubscription<Object?> subscription = dataSource
        .systemTranscriptionStream
        .listen((_) {});

    dataSource.sendAudio(_chunk(AudioSource.output, 1000, voiced: true));
    dataSource.sendAudio(_chunk(AudioSource.output, 31000, voiced: true));

    expect(_messageTypes(system.sent).last, 'input_audio_buffer.commit');
    expect(jsonDecode(system.sent.last), containsPair('final', true));
    expect(dataSource.activeSources, <AudioSource>{AudioSource.output});
    system.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': 'client',
    });
    await Future<void>.delayed(Duration.zero);
    expect(dataSource.activeSources, isEmpty);
    await subscription.cancel();
  });

  test('attend tous les done quand plusieurs commits sont en vol', () async {
    await dataSource.connect();
    final StreamSubscription<Object?> subscription = dataSource
        .transcriptionStream
        .listen((_) {});

    dataSource.sendAudio(_chunk(AudioSource.input, 1000, voiced: true));
    dataSource.sendAudio(_chunk(AudioSource.input, 1801, voiced: false));
    dataSource.sendAudio(_chunk(AudioSource.input, 2000, voiced: true));
    dataSource.sendAudio(_chunk(AudioSource.input, 2801, voiced: false));

    expect(
      _messageTypes(
        mic.sent,
      ).where((String type) => type == 'input_audio_buffer.commit'),
      hasLength(2),
    );
    expect(dataSource.activeSources, <AudioSource>{AudioSource.input});

    mic.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': 'premier',
    });
    await Future<void>.delayed(Duration.zero);
    expect(dataSource.activeSources, <AudioSource>{AudioSource.input});

    mic.emit(<String, Object>{
      'type': 'response.audio_transcript.done',
      'text': 'second',
    });
    await Future<void>.delayed(Duration.zero);
    expect(dataSource.activeSources, isEmpty);
    await subscription.cancel();
  });

  test('décode indépendamment les événements micro et système', () async {
    await dataSource.connect();
    final Future<String?> micDelta = dataSource.transcriptionStream.first.then(
      (event) => event.delta,
    );
    final Future<String?> systemDelta = dataSource
        .systemTranscriptionStream
        .first
        .then((event) => event.delta);

    mic.emit(<String, Object>{
      'type': 'response.audio_transcript.delta',
      'delta': 'moi',
    });
    system.emit(<String, Object>{
      'type': 'response.audio_transcript.delta',
      'delta': 'client',
    });

    expect(await micDelta, 'moi');
    expect(await systemDelta, 'client');
  });
}

AudioChunk _chunk(AudioSource source, int timestampMs, {required bool voiced}) {
  final Uint8List data = Uint8List(3200);
  if (voiced) {
    final ByteData samples = ByteData.sublistView(data);
    for (int offset = 0; offset < data.length; offset += 2) {
      samples.setInt16(offset, 1200, Endian.little);
    }
  }
  return AudioChunk(source: source, data: data, timestampMs: timestampMs);
}

List<String> _messageTypes(List<String> messages) => messages
    .map(
      (String message) =>
          (jsonDecode(message) as Map<String, dynamic>)['type'] as String,
    )
    .toList();

final class _FakeWebSocketClient implements WebSocketClient {
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final List<String> sent = <String>[];
  int connectCalls = 0;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get messageStream => _messages.stream;

  @override
  Future<void> connect(String url) async {
    connectCalls++;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  void send(String message) {
    if (_connected) sent.add(message);
  }

  void emit(Map<String, Object> event) => _messages.add(jsonEncode(event));

  @override
  Future<void> dispose() async {
    _connected = false;
    await _messages.close();
  }
}
