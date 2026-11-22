import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_data/clients/websocket_client.dart';
import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:rxdart/rxdart.dart';

/// Implementation WebSocket avec DEUX flux séparés (Path A) :
/// - micro (input) → transcript "MOI"
/// - audio système (output) → transcript des interlocuteurs distants
///
/// voxmlx-serve gère une session indépendante par connexion WebSocket, donc on
/// ouvre deux connexions vers le même serveur. Aucun mixage : chaque source est
/// transcrite séparément et taguée correctement.
///
/// Une socket qui tombe ne perd pas l'audio : tout ce qui n'a pas encore son
/// `done` (envoyé ou non) est gardé dans l'ordre, au plus [_maxBufferedMs]
/// par source. La socket est rouverte avec un délai croissant, puis cet
/// audio repart avant l'audio en direct : une phrase partie sur la socket
/// morte est donc retranscrite en entier. Au-delà de la borne, le plus
/// ancien est jeté et signalé par [audioGaps].
final class TranscriptionRemoteDataSourceImpl
    implements TranscriptionRemoteDataSource {
  /// Cree une instance de [TranscriptionRemoteDataSourceImpl].
  TranscriptionRemoteDataSourceImpl({
    WebSocketClient? micClient,
    WebSocketClient? systemClient,
  }) : _mic = micClient ?? WebSocketClient(),
       _sys = systemClient ?? WebSocketClient();

  final WebSocketClient _mic;
  final WebSocketClient _sys;
  bool _systemConnected = false;
  String _url = 'ws://localhost:8000/v1/realtime';

  // Gate de silence (VAD simple) : chaque source possède son propre tour de
  // parole. Une pause finalise explicitement la session voxmlx correspondante,
  // ce qui borne les caches du modèle et évite la dérive sur les appels longs.
  static const int _voiceThreshold = 350; // amplitude int16 ~ parole
  static const double _voiceStartRms = 300;
  static const double _voiceContinueRms = 180;
  // Une respiration au milieu d'une phrase dépasse souvent 0,7 s : en dessous
  // de ~1,2 s, une même phrase était coupée en plusieurs lignes.
  static const int _silenceToFinalizeMs = 1200;
  static const int _maxUtteranceMs = 30000;
  // Une phrase restée moins longtemps au-dessus du seuil de parole est
  // marquée sans parole (UtteranceWindow.hadSpeech) : filtre d'hallucinations.
  static const int _minSpeechMs = 300;
  // PCM16 mono 16 kHz.
  static const int _bytesPerMs = 32;

  // Coupure : au moins 120 s d'audio gardées par source, reconnexion de
  // 0,5 s à 10 s au plus (la reprise suit vite le retour du serveur).
  static const int _maxBufferedMs = 120000;
  // Renvoi étalé : au plus 30 s d'audio envoyé sans `done` à la fois ; la
  // suite part au `done` précédent (sonde : 31 s renvoyées d'un bloc à côté
  // d'un flux direct ont fait monter un `done` à 38,8 s).
  static const int _maxInFlightMs = 30000;
  static const Duration _firstRetryDelay = Duration(milliseconds: 500);
  static const Duration _maxRetryDelay = Duration(seconds: 10);
  // Serveur muet. Le vrai serveur traite les sockets l'une après l'autre :
  // pendant un rattrapage, un `done` a mis 38,8 s et deux `done` ont été
  // séparés de 28,9 s, serveur vivant (sonde 2026-11-22). La vivacité se
  // juge donc sur TOUT message du serveur, sur toutes ses sockets : seul un
  // silence total de [_serverSilence] alors qu'un commit final attend fait
  // recycler les sockets en attente et renvoyer leurs phrases ; après
  // [_maxSilentRecycles] recyclages sans réponse, l'audio sans `done` est
  // déclaré perdu.
  static const Duration _serverSilence = Duration(seconds: 60);
  static const int _maxSilentRecycles = 3;
  Timer? _silenceTimer;
  final Map<AudioSource, int> _silentRecycles = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, _Unacked> _unacked = <AudioSource, _Unacked>{
    AudioSource.input: _Unacked(_maxBufferedMs),
    AudioSource.output: _Unacked(_maxBufferedMs),
  };
  // Reconnexion en cours, par source (null : socket vivante).
  final Map<AudioSource, _Outage?> _outages = <AudioSource, _Outage?>{
    AudioSource.input: null,
    AudioSource.output: null,
  };
  final PublishSubject<AudioGap> _gapSubject = PublishSubject<AudioGap>();
  // Événements émis par la source elle-même sur le flux d'une source.
  final Map<AudioSource, PublishSubject<TranscriptEventRemoteModel>> _control =
      <AudioSource, PublishSubject<TranscriptEventRemoteModel>>{
        AudioSource.input: PublishSubject<TranscriptEventRemoteModel>(),
        AudioSource.output: PublishSubject<TranscriptEventRemoteModel>(),
      };
  final Map<AudioSource, int> _voicedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, int> _lastVoicedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, int> _utteranceStartedMs = <AudioSource, int>{
    AudioSource.input: 0,
    AudioSource.output: 0,
  };
  final Map<AudioSource, bool> _utteranceActive = <AudioSource, bool>{
    AudioSource.input: false,
    AudioSource.output: false,
  };
  // Intervalles des phrases dont le commit final est parti sur la socket
  // vivante, dans l'ordre des `done` attendus.
  final Map<AudioSource, Queue<UtteranceWindow>> _pendingWindows =
      <AudioSource, Queue<UtteranceWindow>>{
        AudioSource.input: Queue<UtteranceWindow>(),
        AudioSource.output: Queue<UtteranceWindow>(),
      };
  final Expando<UtteranceWindow> _eventWindows = Expando<UtteranceWindow>();

  final BehaviorSubject<domain.ConnectionState> _connectionStateSubject =
      BehaviorSubject<domain.ConnectionState>.seeded(
        domain.ConnectionState.disconnected,
      );

  @override
  Future<void> connect({
    String url = 'ws://localhost:8000/v1/realtime',
    bool systemAudioEnabled = true,
  }) async {
    _connectionStateSubject.add(domain.ConnectionState.connecting);
    _url = url;
    _systemConnected = systemAudioEnabled;
    _clearOutages();
    _resetUtteranceState();
    try {
      await Future.wait(<Future<void>>[
        _mic.connect(url),
        if (systemAudioEnabled) _sys.connect(url) else _sys.disconnect(),
      ]);
      _connectionStateSubject.add(domain.ConnectionState.connected);
    } catch (_) {
      await Future.wait(<Future<void>>[_mic.disconnect(), _sys.disconnect()]);
      _connectionStateSubject.add(domain.ConnectionState.error);
      rethrow;
    }
  }

  @override
  void sendAudio(AudioChunk chunk) {
    final AudioSource source = chunk.source;
    if (source == AudioSource.output && !_systemConnected) return;
    final int now = chunk.timestampMs;
    final double? rms = _speechRms(chunk.data);
    final bool voiced =
        rms != null &&
        rms >= (_utteranceActive[source]! ? _voiceContinueRms : _voiceStartRms);

    if (voiced) {
      if (!_utteranceActive[source]!) {
        _utteranceActive[source] = true;
        _utteranceStartedMs[source] = now;
        _voicedMs[source] = 0;
      }
      _lastVoicedMs[source] = now;
      // Seul l'audio au-dessus du seuil d'ouverture compte comme parole ;
      // entre les deux seuils, il prolonge la phrase sans en être.
      if (rms >= _voiceStartRms) {
        _voicedMs[source] =
            _voicedMs[source]! + chunk.data.length ~/ _bytesPerMs;
      }
      _sendChunk(chunk);

      // Même sans pause, borner une session évite que l'état incrémental du
      // modèle dérive après plusieurs minutes (langue parasite / ponctuation).
      if (now - _utteranceStartedMs[source]! >= _maxUtteranceMs) {
        _finalizeSource(source);
      }
      return;
    }

    if (!_utteranceActive[source]!) {
      return;
    }

    // Conserver une courte queue de silence pour ne pas couper la fin du mot.
    if (now - _lastVoicedMs[source]! <= _silenceToFinalizeMs) {
      _sendChunk(chunk);
      return;
    }

    _finalizeSource(source);
  }

  void _sendChunk(AudioChunk chunk) {
    _send(
      chunk.source,
      jsonEncode(<String, String>{
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk.data),
      }),
      timestampMs: chunk.timestampMs,
      audioMs: chunk.data.length ~/ _bytesPerMs,
    );
  }

  WebSocketClient _client(AudioSource source) =>
      source == AudioSource.input ? _mic : _sys;

  /// Envoie [message] sur la socket de [source] si elle vit, et le garde
  /// jusqu'au `done` qui l'acquitte. [window] est attendue en retour d'un
  /// `done` une fois le commit final réellement écrit sur une socket vivante.
  void _send(
    AudioSource source,
    String message, {
    int? timestampMs,
    int audioMs = 0,
    UtteranceWindow? window,
  }) {
    final WebSocketClient client = _client(source);
    // ponytail: la coupure n'est vue qu'au prochain envoi (pas d'écoute de
    // fermeture) ; pendant un silence, la reconnexion attend la parole
    // suivante. Écouter la fermeture du canal si le délai gêne.
    final bool live = _outages[source] == null && client.isConnected;
    if (!live && _outages[source] == null) _startOutage(source);
    _unacked[source]!.add(_Outgoing(message, timestampMs, audioMs, window));
    if (live) _pump(source);
  }

  /// Envoie, dans l'ordre, ce que la borne de [_maxInFlightMs] autorise.
  void _pump(AudioSource source) {
    final WebSocketClient client = _client(source);
    final _Unacked unacked = _unacked[source]!;
    while (client.isConnected) {
      final _Outgoing? item = unacked.nextSendable(_maxInFlightMs);
      if (item == null) return;
      client.send(item.message);
      if (item.window != null) _awaitDone(source, item.window!);
    }
  }

  /// [window] part sur la socket vivante : son `done` est attendu.
  void _awaitDone(AudioSource source, UtteranceWindow window) {
    _pendingWindows[source]!.add(window);
    _silenceTimer ??= Timer(_serverSilence, _onServerSilence);
  }

  /// Un message du serveur, sur n'importe quelle socket : il est vivant.
  void _onServerMessage() {
    for (final AudioSource source in AudioSource.values) {
      _silentRecycles[source] = 0;
    }
    _rearmSilence();
  }

  void _rearmSilence() {
    _silenceTimer?.cancel();
    _silenceTimer =
        _pendingWindows.values.any((Queue<UtteranceWindow> q) => q.isNotEmpty)
        ? Timer(_serverSilence, _onServerSilence)
        : null;
  }

  void _onServerSilence() {
    _silenceTimer = null;
    for (final AudioSource source in AudioSource.values) {
      _onSilentServer(source);
    }
    _rearmSilence();
  }

  void _onSilentServer(AudioSource source) {
    if (_outages[source] != null || _pendingWindows[source]!.isEmpty) return;
    final int recycles = _silentRecycles[source]! + 1;
    if (recycles > _maxSilentRecycles) {
      // Abandon : une seule perte couvre l'audio sans réponse, qui n'est plus
      // renvoyé. La socket reste ouverte pour l'audio suivant.
      _silentRecycles[source] = 0;
      _pendingWindows[source]!.clear();
      final _Unacked unacked = _unacked[source]!..loseAll();
      _emitGap(source, unacked);
      _control[source]!.add(
        const TranscriptEventRemoteModel(type: utteranceLostEventType),
      );
      _connectionStateSubject.add(domain.ConnectionState.error);
      // Socket neuve, sans repasser par la reconnexion (l'état reste
      // `error`) : un `done` tardif d'un commit abandonné ne doit pas être
      // pris pour celui de la phrase suivante, ni compter dans sa borne.
      final WebSocketClient client = _client(source);
      unawaited(
        client
            .connect(_url)
            .catchError((Object _) {}), // le prochain envoi verra la coupure
      );
      return;
    }
    _silentRecycles[source] = recycles;
    unawaited(_client(source).disconnect());
    _startOutage(source);
  }

  void _startOutage(AudioSource source) {
    // Les commits partis sur la socket morte n'auront jamais de `done` : ils
    // repartiront depuis le tampon, avec leur fenêtre.
    _pendingWindows[source]!.clear();
    _unacked[source]!
      ..sentEvictionsLost()
      ..resetSent();
    final _Outage outage = _Outage();
    _outages[source] = outage;
    _connectionStateSubject.add(domain.ConnectionState.connecting);
    _scheduleReconnect(source, outage);
  }

  void _scheduleReconnect(AudioSource source, _Outage outage) {
    final Duration delay =
        _firstRetryDelay * (1 << math.min(outage.attempts, 5));
    outage.retry = Timer(
      delay > _maxRetryDelay ? _maxRetryDelay : delay,
      () => unawaited(_reconnect(source, outage)),
    );
  }

  Future<void> _reconnect(AudioSource source, _Outage outage) async {
    outage.attempts++;
    final WebSocketClient client = _client(source);
    try {
      await client.connect(_url);
    } catch (_) {
      if (identical(_outages[source], outage)) {
        _scheduleReconnect(source, outage);
      }
      return;
    }
    // Session close ou relancée pendant la connexion.
    if (!identical(_outages[source], outage)) return;

    final _Unacked unacked = _unacked[source]!..resetSent();
    _outages[source] = null;
    _pump(source);
    if (!client.isConnected) {
      // Retombée pendant le renvoi : tout repartira de la prochaine socket.
      _outages[source] = outage;
      _pendingWindows[source]!.clear();
      unacked.resetSent();
      _scheduleReconnect(source, outage);
      return;
    }
    final bool lost = unacked.lostStartMs != null;
    _emitGap(source, unacked);
    if (lost || unacked.queue.isNotEmpty) {
      _control[source]!.add(
        TranscriptEventRemoteModel(
          type: lost ? utteranceLostEventType : utteranceResentEventType,
        ),
      );
    }
    if (_outages.values.every((_Outage? o) => o == null)) {
      _connectionStateSubject.add(domain.ConnectionState.connected);
    }
  }

  void _emitGap(AudioSource source, _Unacked unacked) {
    final int? start = unacked.lostStartMs;
    if (start == null) return;
    _gapSubject.add(
      AudioGap(source: source, startMs: start, endMs: unacked.lostEndMs!),
    );
    unacked
      ..lostStartMs = null
      ..lostEndMs = null;
  }

  /// Ferme les coupures et vide le tampon. Seul l'audio d'une source coupée
  /// est perdu (il reste dans le WAV) et signalé : sur une socket vivante,
  /// le serveur l'a reçu, son texte est au moins dans les deltas.
  void _clearOutages() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    for (final AudioSource source in AudioSource.values) {
      _silentRecycles[source] = 0;
      final _Outage? outage = _outages[source];
      outage?.retry?.cancel();
      _outages[source] = null;
      final _Unacked unacked = _unacked[source]!;
      if (outage != null) {
        unacked.loseAll();
        _emitGap(source, unacked);
      } else {
        unacked.clear();
      }
    }
  }

  /// Audio en attente d'envoi pour [source] (coupure ou renvoi étalé).
  Duration bufferedAudio(AudioSource source) =>
      Duration(milliseconds: _unacked[source]!.unsentAudioMs);

  @override
  Stream<AudioGap> get audioGaps => _gapSubject.stream;

  /// RMS d'un chunk, ou null s'il a trop peu d'échantillons forts.
  double? _speechRms(Uint8List data) {
    final ByteData bd = ByteData.sublistView(data);
    int sampleCount = 0;
    int loudSampleCount = 0;
    double sumSquares = 0;
    for (int i = 0; i + 1 < data.length; i += 2) {
      final int sample = bd.getInt16(i, Endian.little);
      sampleCount++;
      if (sample.abs() > _voiceThreshold) loudSampleCount++;
      sumSquares += sample * sample;
    }
    if (sampleCount == 0) return null;

    // Un clic isolé ne doit pas maintenir Voxtral actif. L'hystérésis garde
    // toutefois les fins de mots plus faibles une fois la parole détectée.
    final int minimumLoudSamples = math.max(3, sampleCount ~/ 50);
    if (loudSampleCount < minimumLoudSamples) return null;
    return math.sqrt(sumSquares / sampleCount);
  }

  @override
  Set<AudioSource> sendCommit({bool isFinal = false}) {
    if (!isFinal) {
      const String commit = '{"type":"input_audio_buffer.commit"}';
      _send(AudioSource.input, commit);
      if (_systemConnected) _send(AudioSource.output, commit);
      return <AudioSource>{};
    }
    final Set<AudioSource> finalized = <AudioSource>{};
    for (final AudioSource source in AudioSource.values) {
      if (_utteranceActive[source]! &&
          (source == AudioSource.input || _systemConnected)) {
        finalized.add(source);
        _finalizeSource(source);
      }
    }
    return finalized;
  }

  void _finalizeSource(AudioSource source) {
    const String finalCommit =
        '{"type":"input_audio_buffer.commit","final":true}';
    final int start = _utteranceStartedMs[source]!;
    final int lastVoiced = _lastVoicedMs[source]!;
    _send(
      source,
      finalCommit,
      window: UtteranceWindow(
        startMs: start,
        endMs: lastVoiced > start ? lastVoiced : start,
        hadSpeech: _voicedMs[source]! >= _minSpeechMs,
      ),
    );
    _utteranceActive[source] = false;
    _utteranceStartedMs[source] = 0;
    _lastVoicedMs[source] = 0;
  }

  @override
  Stream<TranscriptEventRemoteModel> get transcriptionStream =>
      Rx.merge(<Stream<TranscriptEventRemoteModel>>[
        _decode(_mic, AudioSource.input),
        _control[AudioSource.input]!.stream,
      ]);

  @override
  Stream<TranscriptEventRemoteModel> get systemTranscriptionStream =>
      Rx.merge(<Stream<TranscriptEventRemoteModel>>[
        _decode(_sys, AudioSource.output),
        _control[AudioSource.output]!.stream,
      ]);

  @override
  Set<AudioSource> get activeSources => _utteranceActive.entries
      .where(
        (MapEntry<AudioSource, bool> entry) =>
            (entry.value ||
                _pendingWindows[entry.key]!.isNotEmpty ||
                _unacked[entry.key]!.hasUnsentFinalCommit) &&
            (entry.key == AudioSource.input || _systemConnected),
      )
      .map((MapEntry<AudioSource, bool> entry) => entry.key)
      .toSet();

  Stream<TranscriptEventRemoteModel> _decode(
    WebSocketClient client,
    AudioSource source,
  ) {
    return client.messageStream
        .where((String message) => message.isNotEmpty)
        .map((String message) {
          final Map<String, dynamic> json =
              jsonDecode(message) as Map<String, dynamic>;
          final TranscriptEventRemoteModel event =
              TranscriptEventRemoteModel.fromJson(json);
          final Queue<UtteranceWindow> windows = _pendingWindows[source]!;
          if (event.type == 'response.audio_transcript.done' &&
              windows.isNotEmpty) {
            _eventWindows[event] = windows.removeFirst();
            _unacked[source]!.acknowledge();
            _pump(source);
          }
          // Limites connues (protocole sans identifiant de phrase) : un
          // `done` spontané du serveur, arrivé pendant qu'un commit attend,
          // est pris pour la réponse à ce commit ; et une seule socket
          // bloquée pendant que l'autre répond ne se distingue pas de la
          // file du serveur. Seuls la borne de 120 s et le repère de perte
          // couvrent ces cas.
          _onServerMessage();
          return event;
        });
  }

  @override
  UtteranceWindow? windowOf(TranscriptEventRemoteModel event) =>
      _eventWindows[event];

  @override
  Future<void> disconnect() async {
    _clearOutages();
    await Future.wait(<Future<void>>[_mic.disconnect(), _sys.disconnect()]);
    _systemConnected = false;
    _resetUtteranceState();
    _connectionStateSubject.add(domain.ConnectionState.disconnected);
  }

  void _resetUtteranceState() {
    for (final AudioSource source in AudioSource.values) {
      _utteranceActive[source] = false;
      _voicedMs[source] = 0;
      _pendingWindows[source]!.clear();
      _utteranceStartedMs[source] = 0;
      _lastVoicedMs[source] = 0;
    }
  }

  /// Libère les ressources (les deux connexions).
  Future<void> dispose() async {
    _clearOutages();
    await _gapSubject.close();
    for (final PublishSubject<TranscriptEventRemoteModel> c
        in _control.values) {
      await c.close();
    }
    await _mic.dispose();
    await _sys.dispose();
    await _connectionStateSubject.close();
  }

  @override
  Stream<domain.ConnectionState> get connectionState =>
      _connectionStateSubject.stream;
}

/// Message en attente pendant une coupure. [timestampMs] n'est renseigné que
/// pour l'audio ; [window] que pour un commit final.
class _Outgoing {
  _Outgoing(this.message, this.timestampMs, this.audioMs, this.window);

  final String message;
  final int? timestampMs;
  final int audioMs;
  final UtteranceWindow? window;
}

/// Reconnexion en cours d'une source.
class _Outage {
  int attempts = 0;
  Timer? retry;
}

/// Messages d'une source sans `done` (envoyés ou en attente), dans l'ordre,
/// bornés à [maxBufferedMs] d'audio : au-delà, le plus ancien est jeté.
class _Unacked {
  _Unacked(this.maxBufferedMs);

  final int maxBufferedMs;
  final Queue<_Outgoing> queue = Queue<_Outgoing>();
  int audioMs = 0;

  /// Audio perdu pour la transcription, pas encore signalé.
  int? lostStartMs;
  int? lostEndMs;

  /// Audio jeté après être parti sur la socket vivante : il sera transcrit
  /// si son `done` arrive, perdu si la socket tombe avant. Une plage par
  /// commit final jeté ([_Range.closed]), plus au plus une plage ouverte.
  final List<_Range> _sentEvicted = <_Range>[];

  // Préfixe de [queue] écrit sur la socket courante.
  int _sentCount = 0;
  int _sentAudioMs = 0;
  int _sentFinals = 0;

  int get unsentAudioMs => queue
      .skip(_sentCount)
      .fold<int>(0, (int sum, _Outgoing o) => sum + o.audioMs);

  bool get hasUnsentFinalCommit =>
      queue.skip(_sentCount).any((_Outgoing o) => o.window != null);

  void add(_Outgoing item) {
    queue.add(item);
    audioMs += item.audioMs;
    while (audioMs > maxBufferedMs) {
      _evictFirst();
      // Un commit resté en tête ne finaliserait que de l'audio jeté.
      while (queue.isNotEmpty && queue.first.timestampMs == null) {
        _evictFirst();
      }
    }
  }

  /// Prochain message à écrire, ou null s'il doit attendre un `done` : plus
  /// de [capMs] d'audio serait en vol. La phrase en vol seule (aucun commit
  /// final envoyé) continue toujours, sinon elle attendrait son propre
  /// commit (une phrase fait au plus 30 s).
  _Outgoing? nextSendable(int capMs) {
    if (_sentCount >= queue.length) return null;
    final _Outgoing item = queue.elementAt(_sentCount);
    if (item.audioMs > 0 &&
        _sentFinals > 0 &&
        _sentAudioMs + item.audioMs > capMs) {
      return null;
    }
    _sentCount++;
    _sentAudioMs += item.audioMs;
    if (item.window != null) _sentFinals++;
    return item;
  }

  /// Nouvelle socket : rien n'y est encore écrit.
  void resetSent() {
    _sentCount = 0;
    _sentAudioMs = 0;
    _sentFinals = 0;
  }

  // Audio écrit puis jeté de la borne : toujours en vol pour le serveur
  // tant que son `done` n'est pas venu, il reste compté dans la borne de
  // renvoi ; seule sa place dans [queue] disparaît.
  void _evictFirst() {
    final bool sent = _sentCount > 0;
    final _Outgoing item = queue.removeFirst();
    if (sent) _sentCount--;
    _evict(item, sent: sent);
  }

  void _forgetSent(_Outgoing item) {
    _sentCount--;
    _sentAudioMs -= item.audioMs;
    if (item.window != null) _sentFinals--;
  }

  /// Un `done` acquitte la plus ancienne phrase : jusqu'à son commit final.
  // ponytail: un `done` qui n'arrive qu'après une coupure ne peut plus
  // acquitter l'audio jeté avant elle : compté perdu (faux repère au pire).
  void acknowledge() {
    if (_sentEvicted.isNotEmpty && _sentEvicted.first.closed) {
      final _Range acked = _sentEvicted.removeAt(0);
      _sentAudioMs -= acked.audioMs;
      _sentFinals--;
      return;
    }
    // Début jeté de cette même phrase.
    for (final _Range range in _sentEvicted) {
      _sentAudioMs -= range.audioMs;
    }
    _sentEvicted.clear();
    while (queue.isNotEmpty) {
      final _Outgoing item = queue.removeFirst();
      audioMs -= item.audioMs;
      if (_sentCount > 0) _forgetSent(item);
      if (item.window != null) return;
    }
  }

  /// La socket est tombée : l'audio jeté après envoi ne sera pas transcrit.
  void sentEvictionsLost() {
    for (final _Range range in _sentEvicted) {
      if (range.startMs != null) _markLost(range.startMs!, range.endMs!);
    }
    _sentEvicted.clear();
  }

  void clear() {
    queue.clear();
    audioMs = 0;
    resetSent();
    _sentEvicted.clear();
    lostStartMs = null;
    lostEndMs = null;
  }

  void loseAll() {
    sentEvictionsLost();
    resetSent();
    while (queue.isNotEmpty) {
      _evict(queue.removeFirst(), sent: false);
    }
  }

  void _evict(_Outgoing item, {required bool sent}) {
    audioMs -= item.audioMs;
    final int? at = item.timestampMs;
    if (!sent) {
      if (at != null) _markLost(at, at + item.audioMs);
      return;
    }
    if (_sentEvicted.isEmpty || _sentEvicted.last.closed) {
      _sentEvicted.add(_Range());
    }
    final _Range open = _sentEvicted.last..audioMs += item.audioMs;
    if (at != null) {
      open.startMs ??= at;
      open.endMs = at + item.audioMs;
    }
    if (item.window != null) open.closed = true;
  }

  void _markLost(int startMs, int endMs) {
    lostStartMs = lostStartMs == null
        ? startMs
        : math.min(lostStartMs!, startMs);
    lostEndMs = lostEndMs == null ? endMs : math.max(lostEndMs!, endMs);
  }
}

class _Range {
  int audioMs = 0;
  int? startMs;
  int? endMs;
  bool closed = false;
}
