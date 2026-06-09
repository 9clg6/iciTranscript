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

  /// Télécharge [url] vers [dest] via `curl -fSL` (suit toutes les
  /// redirections GitHub et échoue proprement, sans fichier tronqué — le
  /// HttpClient maison sauvegardait des fichiers partiels/corrompus).
  Future<void> _download(String url, String dest) async {
    final ProcessResult r = await Process.run(
      '/usr/bin/curl',
      <String>['-fSL', '--retry', '3', '-o', dest, url],
    );
    if (r.exitCode != 0) {
      await _delete(dest);
      throw Exception('Téléchargement échoué ($url): ${r.stderr}');
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
import json, sys, os, tempfile, wave
import numpy as np
import sherpa_onnx
from parakeet_mlx import from_pretrained

mic_wav, sys_wav, seg, emb, pk_model = sys.argv[1:6]
SR = 16000

def has(p):
    return p and p != '/dev/null' and os.path.exists(p) and os.path.getsize(p) > 44

def load_pcm(path):
    # Lecture brute : on ignore la taille déclarée dans l'en-tête WAV (qui peut
    # ne pas avoir été corrigée si la session s'est terminée brutalement) et on
    # lit tous les octets PCM après l'en-tête 44 octets.
    with open(path, 'rb') as f:
        raw = f.read()
    return np.frombuffer(raw[44:], dtype=np.int16)

def write_wav(pcm, path):
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2)
    w.setframerate(SR); w.writeframes(pcm.tobytes()); w.close()

def rms(pcm):
    if pcm.size == 0:
        return 0.0
    x = pcm.astype(np.float32) / 32768.0
    return float(np.sqrt(np.mean(x * x)))

m = from_pretrained(pk_model)
out = {"mic_text": "", "speakers": []}
tmpd = tempfile.mkdtemp()

mic_pcm = load_pcm(mic_wav) if has(mic_wav) else np.zeros(0, dtype=np.int16)
sys_pcm = load_pcm(sys_wav) if has(sys_wav) else np.zeros(0, dtype=np.int16)

# Transcription du micro (= MOI) pour le coach.
if mic_pcm.size > SR // 2:
    p = os.path.join(tmpd, "mic.wav"); write_wav(mic_pcm, p)
    out["mic_text"] = m.transcribe(p, chunk_duration=120.0).text.strip()

# Diarization sur le flux MICRO (la conversation réelle s'y trouve : utilisateur
# + interlocuteurs présents). Le flux système est souvent du bruit de bureau et
# sur-segmente. Repli sur le système si le micro est vide.
src = mic_pcm if mic_pcm.size > SR else (sys_pcm if sys_pcm.size > SR else None)

if src is not None and rms(src) > 0.005:
    p = os.path.join(tmpd, "diar.wav"); write_wav(src, p)
    f32 = src.astype(np.float32) / 32768.0
    cfg = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=seg)),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=emb),
        # threshold 0.8 : 0.5 sur-segmente massivement l'audio réel.
        clustering=sherpa_onnx.FastClusteringConfig(num_clusters=-1, threshold=0.8),
        min_duration_on=0.3, min_duration_off=0.5,
    )
    sd = sherpa_onnx.OfflineSpeakerDiarization(cfg)
    turns = sd.process(f32).sort_by_start_time()

    sentences = m.transcribe(p, chunk_duration=120.0).sentences or []

    def speaker_for(a, b):
        best, bestov = 0, 0.0
        for t in turns:
            ov = max(0.0, min(b, t.end) - max(a, t.start))
            if ov > bestov:
                bestov, best = ov, t.speaker
        return best

    # Remap des ids de cluster (arbitraires) en 0,1,2… par ordre d'apparition.
    remap = {}
    def norm(spk):
        if spk not in remap:
            remap[spk] = len(remap)
        return remap[spk]

    merged = []
    for s in sentences:
        txt = s.text.strip()
        if not txt:
            continue
        spk = norm(speaker_for(s.start, s.end))
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
