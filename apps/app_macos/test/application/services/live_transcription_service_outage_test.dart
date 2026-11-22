import 'dart:async';
import 'dart:typed_data';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_service_fakes.dart';

/// Tour 2 de T1 : coupures en pleine phrase, filtre `hadSpeech` de bout en
/// bout, arrêt pendant une coupure. Le vrai service et la vraie source
/// distante tournent ensemble sur des sockets factices, horloge factice,
/// dépôts en mémoire (jamais la base ni les WAV réels).
void main() {
  late FakeAsync clock;
  late FakeVoxServer server;
  late FakeVoxSocket mic;
  late LiveServiceHarness h;

  void setUpIn(FakeAsync async) {
    clock = async;
    server = FakeVoxServer();
    mic = FakeVoxSocket(server);
    h = LiveServiceHarness(
      async,
      remote: TranscriptionRemoteDataSourceImpl(
        micClient: mic,
        systemClient: FakeVoxSocket(server),
      ),
    )..start(outputEnabled: false);
  }

  /// Un chunk micro de 100 ms à la position [id] × 100 ms de la réunion.
  void say(int fromId, int count, {_Level level = _Level.speech}) {
    for (int id = fromId; id < fromId + count; id++) {
      final int ts = h.t0 + id * 100;
      h.audio.emit(switch (level) {
        _Level.speech => chunk(AudioSource.input, id, timestampMs: ts),
        _Level.silence => chunk(
          AudioSource.input,
          id,
          timestampMs: ts,
          voiced: false,
        ),
        _Level.weak => _weakChunk(id, ts),
      });
      clock.elapse(const Duration(milliseconds: 100));
    }
  }

  void serverSays(String type, String key, String text) =>
      mic.emit(<String, Object>{'type': type, key: text});

  /// Laisse la reconnexion se faire (15 s au plus, plafond de 10 s compris)
  /// avant que le serveur réponde.
  void untilConnected() {
    for (int i = 0; i < 150 && !mic.isConnected; i++) {
      clock.elapse(const Duration(milliseconds: 100));
    }
    expect(mic.isConnected, isTrue, reason: 'reconnexion attendue');
  }

  List<String> texts() => h.segments
      .of(AudioSource.input)
      .map((TranscriptSegmentEntity s) => s.text)
      .toList();

  group('socket coupée en pleine phrase (point 1)', () {
    // Avec le renvoi (point 2), le serveur retranscrit la phrase entière :
    // le `done` suivant la remplace, sans doublon. Garder le provisoire à
    // part ne vaut que si son audio est perdu (voir le test suivant).
    test('coupure courte : la phrase renvoyée remplace son provisoire, une '
        'seule ligne', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        mic.autoReply = false;
        say(0, 10);
        serverSays('response.audio_transcript.delta', 'delta', 'Bonjour à');
        say(10, 30); // le provisoire est sauvé
        expect(texts(), <String>['Bonjour à']);

        mic
          ..refusing = true
          ..drop();
        say(40, 20);
        mic.refusing = false;
        untilConnected();
        say(60, 30);
        say(90, 20, level: _Level.silence); // commit final
        serverSays(
          'response.audio_transcript.delta',
          'delta',
          'Bonjour à tous, on commence.',
        );
        serverSays(
          'response.audio_transcript.done',
          'text',
          'Bonjour à tous, on commence.',
        );
        async.elapse(const Duration(seconds: 1));

        expect(texts(), <String>['Bonjour à tous, on commence.']);
      });
    });

    test('la retranscription ne double pas le provisoire déjà sauvé', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        mic.autoReply = false;
        say(0, 10);
        serverSays('response.audio_transcript.delta', 'delta', 'Bonjour à');
        say(10, 30);

        mic
          ..refusing = true
          ..drop();
        say(40, 20);
        mic.refusing = false;
        untilConnected(); // renvoi de la phrase sur la nouvelle connexion
        say(60, 20);
        serverSays(
          'response.audio_transcript.delta',
          'delta',
          'Bonjour à tous',
        );
        say(80, 30); // nouveau provisoire

        expect(texts(), <String>['Bonjour à tous']);
      });
    });

    test('coupure plus longue que le tampon : le provisoire reste sa propre '
        'ligne, le done suivant en crée une nouvelle', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        mic.autoReply = false;
        say(0, 10);
        serverSays('response.audio_transcript.delta', 'delta', 'Bonjour à');
        say(10, 20);
        expect(texts(), <String>['Bonjour à']);

        mic
          ..refusing = true
          ..drop();
        say(30, 1500); // 150 s de parole : le début de la phrase est perdu
        mic
          ..refusing = false
          ..autoReply = true;
        untilConnected();
        say(1530, 50);
        say(1580, 30, level: _Level.silence);
        async.elapse(const Duration(seconds: 2));

        final List<String> saved = texts();
        expect(saved, contains('Bonjour à'));
        expect(
          saved.where((String t) => t.startsWith('Transcription interrompue')),
          hasLength(1),
        );
        expect(mic.doneSent, greaterThan(0));
        expect(
          saved.where((String t) => t.startsWith('Phrase numéro')),
          hasLength(mic.doneSent),
        );
      });
    });
  });

  group('phrase sans parole et hallucination connue (point 4)', () {
    test('200 ms de parole puis silence : « Thank you. » n est pas sauvé', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        mic.reply = (_) => 'Thank you.';
        say(0, 2);
        say(2, 25, level: _Level.silence);
        async.elapse(const Duration(seconds: 2));

        expect(mic.doneSent, 1);
        expect(texts(), isEmpty);
      });
    });

    // Lecture du besoin (« jamais 300 ms au-dessus du seuil de parole ») :
    // un audio entre 180 et 300 de RMS prolonge la phrase mais ne compte
    // pas comme parole. À confirmer.
    test(
      'interprétation : moins de 300 ms au-dessus du seuil, même '
      'prolongé par un bruit plus faible, « Thank you. » n est pas sauvé',
      () {
        fakeAsync((FakeAsync async) {
          setUpIn(async);
          mic.reply = (_) => 'Thank you.';
          say(0, 1); // 100 ms de parole
          say(1, 10, level: _Level.weak); // bruit sous le seuil, phrase ouverte
          say(11, 25, level: _Level.silence);
          async.elapse(const Duration(seconds: 2));

          expect(mic.doneSent, 1);
          expect(texts(), isEmpty);
        });
      },
    );

    test('avec de la parole, le même « Thank you. » est sauvé', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        mic.reply = (_) => 'Thank you.';
        say(0, 4); // 400 ms de parole
        say(4, 10, level: _Level.weak);
        say(14, 25, level: _Level.silence);
        async.elapse(const Duration(seconds: 2));

        expect(mic.doneSent, 1);
        expect(texts(), <String>['Thank you.']);
      });
    });
  });

  group('arrêt demandé pendant une coupure (point 5)', () {
    test('l arrêt aboutit vite, la session est close normalement, l audio '
        'non transcrit a son repère, plus aucune relance', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        say(0, 100, level: _Level.silence);
        say(100, 50); // phrase commencée à 10 s, partie sur la socket
        mic
          ..refusing = true
          ..drop();
        say(150, 200); // jusqu'à 35 s, en tampon

        bool stopped = false;
        final Duration askedAt = async.elapsed;
        unawaited(h.service.stopTranscription().then((_) => stopped = true));
        while (!stopped &&
            async.elapsed - askedAt < const Duration(seconds: 30)) {
          async.elapse(const Duration(milliseconds: 100));
        }

        expect(stopped, isTrue);
        expect(
          async.elapsed - askedAt,
          lessThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(h.session.status, SessionStatus.completed);

        final TranscriptSegmentEntity marker = h.segments
            .of(AudioSource.input)
            .singleWhere(
              (TranscriptSegmentEntity s) =>
                  s.text.startsWith('Transcription interrompue'),
            );
        expect(marker.timestampMs, 10000);
        expect(marker.text, matches(RegExp(r'00:00:10\s*[–-]\s*00:00:35')));

        final int connectsAtStop = mic.connectCalls;
        mic.refusing = false;
        async.elapse(const Duration(minutes: 5));
        expect(mic.connectCalls, connectsAtStop);
        expect(h.process.starts, hasLength(1));
      });
    });

    test('crash du serveur puis arrêt avant la relance : arrêt rapide, '
        'session close, aucune relance', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        say(0, 30);
        server.up = false;
        mic.drop();
        h.process.crash();
        say(30, 5);

        bool stopped = false;
        final Duration askedAt = async.elapsed;
        unawaited(h.service.stopTranscription().then((_) => stopped = true));
        while (!stopped &&
            async.elapsed - askedAt < const Duration(seconds: 30)) {
          async.elapse(const Duration(milliseconds: 100));
        }

        expect(stopped, isTrue);
        expect(
          async.elapsed - askedAt,
          lessThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(h.session.status, SessionStatus.completed);
        async.elapse(const Duration(minutes: 10));
        expect(h.process.starts, hasLength(1));
      });
    });

    test('arrêt pendant une relance lente : arrêt rapide, session close, '
        'aucune relance de plus', () {
      fakeAsync((FakeAsync async) {
        setUpIn(async);
        say(0, 30);
        h.process.startDuration = const Duration(seconds: 200);
        server.up = false;
        mic.drop();
        h.process.crash();
        say(30, 100); // la relance part et charge le modèle
        expect(h.process.starts, hasLength(2));

        bool stopped = false;
        final Duration askedAt = async.elapsed;
        unawaited(h.service.stopTranscription().then((_) => stopped = true));
        while (!stopped &&
            async.elapsed - askedAt < const Duration(seconds: 30)) {
          async.elapse(const Duration(milliseconds: 100));
        }

        expect(stopped, isTrue);
        expect(
          async.elapsed - askedAt,
          lessThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(h.session.status, SessionStatus.completed);
        async.elapse(const Duration(minutes: 10));
        expect(h.process.starts, hasLength(2));
      });
    });
  });
}

enum _Level { speech, weak, silence }

/// Chunk « faible » : assez fort pour prolonger une phrase déjà ouverte
/// (100 échantillons à 800, RMS ≈ 247, au-dessus de 180), sous le seuil de
/// parole de 300 qui ouvre une phrase.
AudioChunk _weakChunk(int id, int timestampMs) {
  final Uint8List data = Uint8List(3200);
  final ByteData samples = ByteData.sublistView(data);
  for (int i = 2; i < 1600; i++) {
    samples.setInt16(i * 2, i < 102 ? 800 : 150, Endian.little);
  }
  samples.setInt16(0, id & 0x7FFF, Endian.little);
  samples.setInt16(2, id >> 15, Endian.little);
  return AudioChunk(
    source: AudioSource.input,
    data: data,
    timestampMs: timestampMs,
  );
}
