import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:dio/dio.dart';

enum OllamaSetupStage {
  /// Tout est prêt.
  idle,

  /// Téléchargement du binaire ollama (~50 MB).
  downloadingBinary,

  /// Démarrage du daemon ollama.
  startingServer,

  /// Téléchargement du modèle Mistral Small 24B (~14 GB).
  downloadingModel,

  /// Setup terminé.
  ready,

  /// Erreur.
  error,
}

/// Service responsable de l'installation et du cycle de vie d'Ollama.
///
/// Flux complet au premier lancement :
/// 1. Télécharge le binaire `ollama` si absent (~50 MB)
/// 2. Démarre `ollama serve`
/// 3. Tire le modèle Mistral via l'API REST si absent (~4 GB)
class OllamaService {
  OllamaService();

  final Log _log = Log.named('OllamaService');

  static const String _baseUrl = 'http://localhost:11434';
  // Mistral 7B : ~3-5x plus rapide que mistral-small (24B) sur Mac, qualite
  // suffisante pour le coaching et le resume.
  static const String _model = 'mistral';

  /// Garde le modele charge en RAM 15 min entre deux requetes (evite le
  /// rechargement a froid ~14s qui rend la 1re analyse tres lente).
  static const String _keepAlive = '5m';

  /// Borne la taille du transcript envoye au LLM pour limiter la latence.
  /// On garde la fin (partie la plus recente de la reunion).
  static const int _maxTranscriptChars = 8000;
  // Ollama pour macOS est distribué sous forme d'app bundle dans un zip.
  // Le binaire CLI se trouve à Ollama.app/Contents/Resources/ollama.
  static const String _ollamaZipUrl =
      'https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip';

  Process? _ollamaProcess;

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  String get _appSupportDir {
    final String home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/Library/Application Support/IciTranscript';
  }

  String get _binDir => '$_appSupportDir/bin';
  String get _ollamaBin => '$_binDir/ollama';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// S'assure qu'Ollama est opérationnel et que le modèle est disponible.
  ///
  /// [onProgress] est appelé avec l'étape courante et un ratio 0.0–1.0.
  Future<void> ensureReady({
    void Function(OllamaSetupStage stage, double progress)? onProgress,
  }) async {
    // 1 — Binaire
    if (!await _isBinaryAvailable()) {
      await _downloadBinary(
        onProgress: (p) =>
            onProgress?.call(OllamaSetupStage.downloadingBinary, p),
      );
    }

    // 2 — Serveur
    if (!await _isServerRunning()) {
      onProgress?.call(OllamaSetupStage.startingServer, 0);
      await _startServer();
      onProgress?.call(OllamaSetupStage.startingServer, 1);
    }

    // 3 — Modèle
    if (!await _isModelAvailable()) {
      await _pullModel(
        onProgress: (p) =>
            onProgress?.call(OllamaSetupStage.downloadingModel, p),
      );
    }

    onProgress?.call(OllamaSetupStage.ready, 1);
  }

  /// Vérifie si tout est déjà prêt (binaire + serveur + modèle).
  Future<bool> isFullyReady() async {
    if (!await _isBinaryAvailable()) return false;
    if (!await _isServerRunning()) return false;
    return _isModelAvailable();
  }

  /// Analyse l'anglais parlé d'un transcript et renvoie un retour structuré.
  ///
  /// Suppose qu'Ollama est déjà prêt ([ensureReady]).
  Future<EnglishFeedbackEntity> analyzeEnglish(String transcript) async {
    const String system =
        'You are an English coach. The transcript below is the spoken English '
        'of a non-native speaker during a meeting. Identify the most useful '
        'mistakes and improvements. For each, give the original phrase, a '
        'corrected/improved version, a category among "conjugation", '
        '"vocabulary", "expression" or "grammar", and a SHORT explanation IN '
        'FRENCH. Respond ONLY with a JSON object of the exact shape: '
        '{"overall": string, "corrections": [{"original": string, '
        '"corrected": string, "category": string, "explanation": string}]}. '
        'The "overall" field is a short assessment of the level, in French. '
        'Do not invent mistakes: if a sentence is correct, skip it.';

    final String content = await _chat(
      system: system,
      user: 'Transcript:\n\n${_truncate(transcript)}',
      json: true,
    );
    return _parseFeedback(content);
  }

  /// Génère un résumé en français du transcript fourni.
  ///
  /// Suppose qu'Ollama est déjà prêt ([ensureReady]).
  Future<String> summarize(String transcript) async {
    const String system =
        'Tu es un assistant qui résume des réunions en français. Produis un '
        'résumé clair et concis : 1 phrase de contexte, puis 4 à 8 puces '
        '(points clés, décisions, actions). Réponds uniquement avec le résumé, '
        'sans préambule.';

    return _chat(
      system: system,
      user: 'Transcription de la réunion :\n\n${_truncate(transcript)}',
    );
  }

  /// Appel générique à l'API /api/chat d'Ollama (non-stream).
  Future<String> _chat({
    required String system,
    required String user,
    bool json = false,
  }) async {
    final Dio dio = Dio()
      ..options.receiveTimeout = const Duration(minutes: 5);
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': _model,
      'stream': false,
      'keep_alive': _keepAlive,
      // Contexte borné : le défaut 32768 alloue un KV cache de plusieurs Go
      // (mémoire unifiée) et peut faire crasher la machine. Le transcript est
      // tronqué à ~8000 car (~2-3k tokens), 4096 suffit largement.
      'options': <String, dynamic>{'num_ctx': 4096},
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': system},
        <String, String>{'role': 'user', 'content': user},
      ],
    };
    if (json) payload['format'] = 'json';

    final Response<Map<String, dynamic>> response =
        await dio.post<Map<String, dynamic>>(
      '$_baseUrl/api/chat',
      data: payload,
      options: Options(
        headers: <String, String>{'content-type': 'application/json'},
      ),
    );
    final Map<String, dynamic> message =
        response.data?['message'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    return message['content'] as String? ?? '';
  }

  String _truncate(String transcript) {
    if (transcript.length <= _maxTranscriptChars) return transcript;
    return transcript.substring(transcript.length - _maxTranscriptChars);
  }

  EnglishFeedbackEntity _parseFeedback(String content) {
    try {
      final Object? decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return EnglishFeedbackEntity.fromJson(decoded);
      }
    } catch (e) {
      _log.error('Parsing feedback JSON échoué: $e');
    }
    return const EnglishFeedbackEntity(
      overall: 'Impossible de lire la réponse du modèle.',
    );
  }

  /// Arrête le daemon démarré par ce service.
  Future<void> dispose() async {
    _ollamaProcess?.kill(ProcessSignal.sigterm);
    _ollamaProcess = null;
  }

  // ---------------------------------------------------------------------------
  // Binary
  // ---------------------------------------------------------------------------

  Future<bool> _isBinaryAvailable() async {
    // Install système complète disponible → OK (chemin préféré, backends Metal).
    if (await _resolveSystemOllamaPath() != null) return true;
    // Copie locale : valable UNIQUEMENT si les backends ggml sont présents à
    // côté (sinon CPU-only). Une ancienne copie binaire-seul est rejetée pour
    // forcer un re-téléchargement complet.
    if (await File(_ollamaBin).exists() &&
        await File('$_binDir/libggml-base.dylib').exists()) {
      return true;
    }
    return false;
  }

  Future<String?> _resolveSystemOllamaPath() async {
    final String home = Platform.environment['HOME'] ?? '/tmp';
    final List<String> candidates = <String>[
      '$home/.local/bin/ollama',
      '/opt/homebrew/bin/ollama',
      '/usr/local/bin/ollama',
      '/Applications/Ollama.app/Contents/Resources/ollama',
    ];
    for (final String path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  Future<String> _effectiveBinPath() async {
    // Préférer une install système COMPLÈTE (Ollama.app) : elle embarque les
    // backends ggml/Metal (libggml-*.dylib, mlx_metal) à côté du binaire, sans
    // lesquels ollama tourne en CPU-only → 7B sature le CPU et fige la machine.
    final String? sys = await _resolveSystemOllamaPath();
    if (sys != null) return sys;
    return _ollamaBin;
  }

  Future<void> _downloadBinary({
    void Function(double progress)? onProgress,
  }) async {
    _log.info('Téléchargement de Ollama-darwin.zip (~106 MB)...');
    await Directory(_binDir).create(recursive: true);

    final String zipPath = '$_binDir/Ollama-darwin.zip';
    final String extractDir = '$_binDir/_extract';
    final Dio dio = Dio();

    try {
      // 1. Télécharger le zip
      await dio.download(
        _ollamaZipUrl,
        zipPath,
        onReceiveProgress: (int received, int total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
      _log.info('Zip téléchargé: $zipPath');

      // 2. Extraire
      await Directory(extractDir).create(recursive: true);
      final ProcessResult unzip = await Process.run(
        'unzip',
        <String>['-o', '-q', zipPath, '-d', extractDir],
      );
      if (unzip.exitCode != 0) {
        throw Exception('unzip échoué: ${unzip.stderr}');
      }

      // 3. Copier TOUT le contenu de Resources (binaire CLI + backends
      //    ggml/Metal). Copier seulement le binaire le ferait tourner en
      //    CPU-only → 7B sature le CPU et fige la machine.
      final String resourcesDir =
          '$extractDir/Ollama.app/Contents/Resources';
      if (!await File('$resourcesDir/ollama').exists()) {
        throw Exception('Binaire ollama introuvable dans le bundle: '
            '$resourcesDir/ollama');
      }
      final ProcessResult cp = await Process.run(
        '/bin/sh',
        <String>['-c', "cp -R '$resourcesDir/.' '$_binDir/'"],
      );
      if (cp.exitCode != 0) {
        throw Exception('Copie des Resources ollama échouée: ${cp.stderr}');
      }
      await Process.run('chmod', <String>['+x', _ollamaBin]);
      _log.info('Ollama (binaire + backends) extrait dans: $_binDir');
    } finally {
      // Nettoyage même en cas d'erreur
      await File(zipPath).delete().catchError((_) => File(zipPath));
      await Directory(extractDir)
          .delete(recursive: true)
          .catchError((_) => Directory(extractDir));
    }
  }

  // ---------------------------------------------------------------------------
  // Server
  // ---------------------------------------------------------------------------

  Future<bool> _isServerRunning() async {
    try {
      final Dio dio = Dio()
        ..options.connectTimeout = const Duration(seconds: 2)
        ..options.receiveTimeout = const Duration(seconds: 2);
      final Response<dynamic> res =
          await dio.get<dynamic>('$_baseUrl/api/tags');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startServer() async {
    final String bin = await _effectiveBinPath();
    _log.info('Démarrage de "$bin serve"');

    _ollamaProcess = await Process.start(
      bin,
      <String>['serve'],
      environment: <String, String>{
        'HOME': Platform.environment['HOME'] ?? '/tmp',
        'PATH': _extendedPath(),
        // Stocker les modèles dans le répertoire de l'app
        'OLLAMA_MODELS': '$_appSupportDir/models',
      },
      mode: ProcessStartMode.detachedWithStdio,
    );

    _ollamaProcess!.stdout
        .transform(const SystemEncoding().decoder)
        .listen((String l) => _log.debug('[ollama] $l'));
    _ollamaProcess!.stderr
        .transform(const SystemEncoding().decoder)
        .listen((String l) => _log.debug('[ollama-err] $l'));

    // Attendre que le serveur réponde (max 30s)
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (await _isServerRunning()) {
        _log.info('Ollama prêt (${i + 1}s)');
        return;
      }
    }
    throw Exception('Ollama ne répond pas après 30s.');
  }

  String _extendedPath() {
    final String home = Platform.environment['HOME'] ?? '/tmp';
    return <String>[
      '$home/.local/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
    ].join(':');
  }

  // ---------------------------------------------------------------------------
  // Model
  // ---------------------------------------------------------------------------

  Future<bool> _isModelAvailable() async {
    try {
      final Dio dio = Dio();
      final Response<Map<String, dynamic>> res =
          await dio.get<Map<String, dynamic>>('$_baseUrl/api/tags');
      final List<dynamic> models =
          res.data?['models'] as List<dynamic>? ?? <dynamic>[];
      return models.any((dynamic m) {
        final String name = (m as Map<String, dynamic>)['name'] as String? ?? '';
        return name.startsWith(_model);
      });
    } catch (_) {
      return false;
    }
  }

  /// Tire le modèle via l'API REST Ollama (NDJSON stream) pour avoir la progression.
  Future<void> _pullModel({
    void Function(double progress)? onProgress,
  }) async {
    _log.info('Téléchargement du modèle $_model via Ollama API...');

    final HttpClient client = HttpClient();
    final HttpClientRequest request =
        await client.post('localhost', 11434, '/api/pull');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{
      'name': _model,
      'stream': true,
    }));

    final HttpClientResponse response = await request.close();

    await for (final String chunk
        in response.transform(const SystemEncoding().decoder)) {
      // Plusieurs JSON peuvent arriver dans un même chunk
      for (final String line in chunk.split('\n')) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final Map<String, dynamic> event =
              jsonDecode(trimmed) as Map<String, dynamic>;
          final String status = event['status'] as String? ?? '';
          final int total = event['total'] as int? ?? 0;
          final int completed = event['completed'] as int? ?? 0;

          if (total > 0 && status.startsWith('pulling')) {
            onProgress?.call(completed / total);
          } else if (status == 'success') {
            onProgress?.call(1.0);
            _log.info('Modèle $_model téléchargé');
          }
        } catch (_) {
          // Ligne non-JSON, ignorer
        }
      }
    }

    client.close();
  }
}
