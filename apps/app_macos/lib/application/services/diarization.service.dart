import 'dart:convert';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';

/// Résultat brut de la passe post-session.
class DiarizationResult {
  const DiarizationResult({this.micText, this.speakers = const <SpeakerTurn>[]});
  final String? micText;
  final List<SpeakerTurn> speakers;
}

/// Service de traitement post-session (Path B) :
/// - transcrit le micro (MOI) proprement,
/// - diarize + transcrit le flux système (Interlocuteur N),
/// via un script Python (voxmlx + sherpa-onnx) lancé avec `uv`.
class DiarizationService {
  DiarizationService();

  final Log _log = Log.named('DiarizationService');

  // Parakeet 0.6B (multilingue, MLX) : ~7x plus léger que Voxtral 4B → moins
  // de pression mémoire/GPU + timestamps natifs pour l'alignement diarization.
  static const String _pkModel = 'mlx-community/parakeet-tdt-0.6b-v3';
  static const String _segUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';
  static const String _embUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_titanet_small.onnx';

  String get _home => Platform.environment['HOME'] ?? '/tmp';
  String get _appSupportDir =>
      '$_home/Library/Application Support/IciTranscript';
  String get _recordingsDir => '$_appSupportDir/recordings';
  String get _diarDir => '$_appSupportDir/diar';
  String get _scriptPath => '$_diarDir/process_session.py';
  String get _segModel => '$_diarDir/segmentation.onnx';
  String get _embModel => '$_diarDir/embedding.onnx';
  String get _uvBin => '$_home/.local/bin/uv';

  /// Chemins WAV par session (écrits par [LiveTranscriptionService]).
  String micWavPath(String sessionId) =>
      '$_recordingsDir/${sessionId}_mic.wav';
  String systemWavPath(String sessionId) =>
      '$_recordingsDir/${sessionId}_system.wav';
  String get recordingsDir => _recordingsDir;

  /// Traite une session : renvoie la transcription propre (MOI + speakers).
  /// Renvoie null si aucun enregistrement exploitable.
  Future<DiarizationResult?> processSession(String sessionId) async {
    final String mic = micWavPath(sessionId);
    final String sys = systemWavPath(sessionId);
    final bool hasMic = await _hasAudio(mic);
    final bool hasSys = await _hasAudio(sys);
    if (!hasMic && !hasSys) {
      _log.info('Aucun enregistrement pour $sessionId, skip diarization');
      return null;
    }

    await _ensureScript();
    await _ensureModels();

    _log.info('Lancement passe post-session pour $sessionId');
    final ProcessResult result = await Process.run(
      _uvBin,
      <String>[
        'run',
        '--python', '3.12',
        '--with', 'parakeet-mlx',
        '--with', 'sherpa-onnx',
        '--with', 'numpy',
        'python',
        _scriptPath,
        hasMic ? mic : '/dev/null',
        hasSys ? sys : '/dev/null',
        _segModel,
        _embModel,
        _pkModel,
      ],
      environment: <String, String>{
        'HOME': _home,
        'PATH': _extendedPath(),
      },
    );

    if (result.exitCode != 0) {
      _log.error('Script post-session échoué (${result.exitCode}): '
          '${result.stderr}');
      return null;
    }

    // La dernière ligne stdout est le JSON (les libs loggent au-dessus).
    final String out = (result.stdout as String).trim();
    final String jsonLine = out.split('\n').lastWhere(
          (String l) => l.trim().startsWith('{'),
          orElse: () => '',
        );
    if (jsonLine.isEmpty) {
      _log.error('Pas de JSON en sortie du script post-session');
      return null;
    }

    try {
      final Map<String, dynamic> j =
          jsonDecode(jsonLine) as Map<String, dynamic>;
      final List<dynamic> sp = j['speakers'] as List<dynamic>? ?? <dynamic>[];
      final DiarizationResult r = DiarizationResult(
        micText: (j['mic_text'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['mic_text'] as String).trim(),
        speakers: sp
            .whereType<Map<String, dynamic>>()
            .map(SpeakerTurn.fromJson)
            .toList(),
      );
      _log.info('Post-session OK : ${r.speakers.length} tours');
      // Nettoyage des WAV (volumineux) une fois traités.
      await _delete(mic);
      await _delete(sys);
      return r;
    } catch (e) {
      _log.error('Parsing JSON post-session échoué: $e');
      return null;
    }
  }

  Future<bool> _hasAudio(String path) async {
    final File f = File(path);
    if (!await f.exists()) return false;
    // > en-tête WAV (44 o) + un minimum d'échantillons.
    return await f.length() > 16000; // ~0.5s @16k mono int16
  }

  Future<void> _delete(String path) async {
    try {
      final File f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _ensureScript() async {
    final File f = File(_scriptPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(_pyScript);
  }

  Future<void> _ensureModels() async {
    if (!await File(_embModel).exists()) {
      _log.info('Téléchargement modèle embedding…');
      await _download(_embUrl, _embModel);
    }
    if (!await File(_segModel).exists()) {
      _log.info('Téléchargement modèle segmentation…');
      final String tar = '$_diarDir/seg.tar.bz2';
      await _download(_segUrl, tar);
      final String extract = '$_diarDir/_seg';
      await Directory(extract).create(recursive: true);
      await Process.run('tar', <String>['xjf', tar, '-C', extract]);
      final File m = File(
        '$extract/sherpa-onnx-pyannote-segmentation-3-0/model.onnx',
      );
      if (await m.exists()) {
        await m.copy(_segModel);
      }
      await _delete(tar);
      await Directory(extract).delete(recursive: true).catchError(
            (_) => Directory(extract),
          );
    }
  }

  Future<void> _download(String url, String dest) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse res = await req.close();
      if (res.statusCode >= 300 && res.statusCode < 400) {
        // Suivre la redirection GitHub.
        final String? loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc != null) {
          await _download(loc, dest);
          return;
        }
      }
      final IOSink sink = File(dest).openWrite();
      await res.pipe(sink);
    } finally {
      client.close();
    }
  }

  String _extendedPath() => <String>[
        '$_home/.local/bin',
        '$_home/.cargo/bin',
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
        '/bin',
      ].join(':');

  /// Script Python embarqué (écrit dans le dossier de l'app au runtime).
  ///
  /// Transcription : Parakeet MLX (multilingue, léger). Diarization : sherpa.
  /// Alignement : chaque phrase (timestamps Parakeet) est attribuée au tour de
  /// parole (sherpa) avec lequel elle chevauche le plus.
  static const String _pyScript = r'''
import json, sys, wave, os
import numpy as np
import sherpa_onnx
from parakeet_mlx import from_pretrained

mic_wav, sys_wav, seg, emb, pk_model = sys.argv[1:6]

def has(p):
    return p and p != '/dev/null' and os.path.exists(p) and os.path.getsize(p) > 44

m = from_pretrained(pk_model)
out = {"mic_text": "", "speakers": []}

if has(mic_wav):
    out["mic_text"] = m.transcribe(mic_wav).text.strip()

if has(sys_wav):
    w = wave.open(sys_wav); sr = w.getframerate()
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    f32 = pcm.astype(np.float32) / 32768.0
    cfg = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=seg)),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=emb),
        clustering=sherpa_onnx.FastClusteringConfig(num_clusters=-1, threshold=0.5),
        min_duration_on=0.3, min_duration_off=0.5,
    )
    sd = sherpa_onnx.OfflineSpeakerDiarization(cfg)
    turns = sd.process(f32).sort_by_start_time()

    res = m.transcribe(sys_wav)
    sentences = res.sentences if res.sentences else []

    def speaker_for(a, b):
        best, bestov = 0, 0.0
        for t in turns:
            ov = max(0.0, min(b, t.end) - max(a, t.start))
            if ov > bestov:
                bestov, best = ov, t.speaker
        return best

    merged = []
    for s in sentences:
        spk = speaker_for(s.start, s.end)
        txt = s.text.strip()
        if not txt:
            continue
        if merged and merged[-1]["speaker"] == spk:
            merged[-1]["end"] = round(s.end, 2)
            merged[-1]["text"] += " " + txt
        else:
            merged.append({"speaker": spk, "start": round(s.start, 2),
                           "end": round(s.end, 2), "text": txt})
    out["speakers"] = merged

print(json.dumps(out, ensure_ascii=False))
''';
}
