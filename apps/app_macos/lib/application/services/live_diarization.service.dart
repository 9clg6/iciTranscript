import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Diarization en temps réel de l'audio système (interlocuteurs distants).
///
/// Lance le serveur `nemotron_diar_mlx.server` (NVIDIA Nemotron 3
/// Diarization en MLX, preset basse latence) avec `uv`, lui envoie le PCM du
/// flux système et reçoit, avec ~1 s de retard, la probabilité d'activité de
/// chaque interlocuteur toutes les 10 ms. [resolve] retrouve l'interlocuteur
/// dominant sur un intervalle exprimé en horodatages de capture.
///
/// Tout est best effort : si le serveur n'est pas (encore) prêt, la
/// transcription continue sans étiquettes.
class LiveDiarizationService {
  LiveDiarizationService();

  static const int port = 8001;
  static const int _sampleRate = 16000;

  final Log _log = Log.named('LiveDiarizationService');

  Process? _process;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _done;
  int _generation = 0;

  // Correspondance horodatage de capture -> position dans le flux envoyé.
  final List<int> _chunkEpochMs = <int>[];
  final List<int> _chunkEndSample = <int>[];
  int _samplesSent = 0;

  // Probabilités reçues, une ligne par trame.
  final List<Float32List> _frames = <Float32List>[];
  double _frameDuration = 0.01;

  final StreamController<void> _updates = StreamController<void>.broadcast();

  /// Émis à chaque nouveau lot de trames reçu.
  Stream<void> get updates => _updates.stream;

  /// Vrai quand l'audio envoyé est diarisé.
  bool get isConnected => _channel != null;

  String get _home => Platform.environment['HOME'] ?? '/tmp';

  /// Démarre le serveur puis la session. Retourne quand la diarization est
  /// prête, ou lève une exception (téléchargement, démarrage…).
  Future<void> start() async {
    await stop();
    final int generation = ++_generation;
    _reset();

    // Un serveur orphelin d'une session précédente garderait le port.
    await Process.run('/usr/bin/pkill', <String>[
      '-f',
      'nemotron_diar_mlx.server',
    ]);

    _log.info('Démarrage du serveur de diarization en direct');
    final Process process = await Process.start(
      '$_home/.local/bin/uv',
      <String>[
        'run',
        '--python',
        '3.12',
        '--with',
        DiarizationService.liveServerPackage,
        'python',
        '-m',
        'nemotron_diar_mlx.server',
        '--port',
        '$port',
        '--preset',
        'low_latency',
        '--cache-dir',
        DiarizationService.modelCacheDir,
        '--parent-pid',
        '$pid',
      ],
      environment: <String, String>{
        'HOME': _home,
        'PATH': DiarizationService.extendedPath,
      },
    );
    _process = process;
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((String l) => _log.debug('[diar] ${l.trim()}'));
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((String l) => _log.debug('[diar] ${l.trim()}'));
    unawaited(
      process.exitCode.then((int code) {
        if (identical(_process, process)) {
          _log.info('Serveur de diarization arrêté ($code)');
          _process = null;
          _closeChannel();
        }
      }),
    );

    // Premier lancement : environnement uv + modèle (~400 Mo) + préchauffage.
    final bool healthy = await _waitHealthy(
      generation,
      const Duration(minutes: 20),
    );
    if (!healthy || generation != _generation) {
      throw StateError('Serveur de diarization indisponible');
    }

    final WebSocketChannel channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:$port/v1/diarize'),
    );
    await channel.ready;
    if (generation != _generation) {
      await channel.sink.close();
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object e) => _log.warning('WebSocket diarization: $e'),
      onDone: () => _channel = null,
    );
    _log.info('Diarization en direct active');
  }

  /// Envoie un bloc PCM 16 bits mono 16 kHz capté à [epochMs] (fin du bloc).
  void sendAudio(Uint8List pcm, int epochMs) {
    final WebSocketChannel? channel = _channel;
    if (channel == null || pcm.isEmpty) return;
    channel.sink.add(pcm);
    _samplesSent += pcm.length ~/ 2;
    _chunkEpochMs.add(epochMs);
    _chunkEndSample.add(_samplesSent);
  }

  /// Interlocuteur dominant entre [startEpochMs] et [endEpochMs].
  ///
  /// `covered` est faux tant que les trames de la fin de l'intervalle ne sont
  /// pas arrivées. `speaker` est null si aucune voix n'est assez active.
  ({bool covered, int? speaker}) resolve(
    int startEpochMs,
    int endEpochMs, {
    double minActivity = 0.3,
  }) {
    if (_chunkEpochMs.isEmpty || _frames.isEmpty) {
      return (covered: false, speaker: null);
    }
    // Phrase antérieure à la connexion : rien n'a été diarisé pour elle.
    if (endEpochMs <= _chunkEpochMs.first - 100) {
      return (covered: true, speaker: null);
    }
    final int a = (_sampleAt(startEpochMs) / _samplesPerFrame).floor();
    final int b = math.max(
      a + 1,
      (_sampleAt(endEpochMs) / _samplesPerFrame).ceil(),
    );
    final bool covered = b <= _frames.length;
    final int end = math.min(b, _frames.length);
    if (a >= end) return (covered: covered, speaker: null);
    final int speakers = _frames.first.length;
    final List<double> sums = List<double>.filled(speakers, 0);
    for (int f = a; f < end; f++) {
      for (int s = 0; s < speakers; s++) {
        sums[s] += _frames[f][s];
      }
    }
    int best = 0;
    for (int s = 1; s < speakers; s++) {
      if (sums[s] > sums[best]) best = s;
    }
    final double mean = sums[best] / (end - a);
    return (covered: covered, speaker: mean >= minActivity ? best : null);
  }

  /// Termine la session : attend les dernières trames (au plus [timeout]).
  Future<void> finish({Duration timeout = const Duration(seconds: 8)}) async {
    final WebSocketChannel? channel = _channel;
    if (channel == null) return;
    _done = Completer<void>();
    channel.sink.add(jsonEncode(<String, String>{'type': 'flush'}));
    try {
      await _done!.future.timeout(timeout);
    } on TimeoutException {
      _log.warning('Flush de la diarization en direct expiré');
    }
  }

  /// Arrête la session et le serveur (libère la mémoire GPU).
  Future<void> stop() async {
    _generation++;
    _closeChannel();
    final Process? process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode
          .timeout(const Duration(seconds: 3), onTimeout: () => -1);
      // `uv run` lance python en sous-processus : nettoyer par motif.
      await Process.run('/usr/bin/pkill', <String>[
        '-f',
        'nemotron_diar_mlx.server',
      ]);
    }
  }

  // ---------------------------------------------------------------------------

  double get _samplesPerFrame => _frameDuration * _sampleRate;

  void _reset() {
    _chunkEpochMs.clear();
    _chunkEndSample.clear();
    _samplesSent = 0;
    _frames.clear();
    _frameDuration = 0.01;
  }

  void _closeChannel() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    if (_done != null && !_done!.isCompleted) _done!.complete();
  }

  /// Position (échantillons) de l'instant [epochMs] dans le flux envoyé.
  /// Chaque bloc est horodaté à sa fin ; on interpole à l'intérieur.
  double _sampleAt(int epochMs) {
    int lo = 0;
    int hi = _chunkEpochMs.length - 1;
    if (epochMs >= _chunkEpochMs[hi]) return _chunkEndSample[hi].toDouble();
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_chunkEpochMs[mid] < epochMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final int end = _chunkEndSample[lo];
    final int start = lo == 0 ? 0 : _chunkEndSample[lo - 1];
    final double back = (_chunkEpochMs[lo] - epochMs) * _sampleRate / 1000;
    return math.max(start.toDouble(), end - back);
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    switch (msg['type']) {
      case 'ready':
        _frameDuration = (msg['frame_duration'] as num?)?.toDouble() ?? 0.01;
      case 'frames':
        final int start = (msg['start_frame'] as num).toInt();
        final List<dynamic> rows = msg['probs'] as List<dynamic>;
        // Les trames arrivent dans l'ordre ; on ignore un éventuel recouvrement.
        for (int i = math.max(0, _frames.length - start); i < rows.length; i++) {
          final List<dynamic> row = rows[i] as List<dynamic>;
          _frames.add(
            Float32List.fromList(<double>[
              for (final dynamic v in row) (v as num).toDouble(),
            ]),
          );
        }
        _updates.add(null);
      case 'done':
        if (_done != null && !_done!.isCompleted) _done!.complete();
      case 'error':
        _log.warning('Diarization en direct: ${msg['message']}');
    }
  }

  Future<bool> _waitHealthy(int generation, Duration timeout) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 1);
    final Stopwatch watch = Stopwatch()..start();
    try {
      while (watch.elapsed < timeout) {
        if (generation != _generation || _process == null) return false;
        try {
          final HttpClientRequest request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/health'),
          );
          final HttpClientResponse response = await request.close();
          await response.drain<void>();
          if (response.statusCode == HttpStatus.ok) return true;
        } on Object {
          // Pas encore lancé / modèle en chargement.
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
