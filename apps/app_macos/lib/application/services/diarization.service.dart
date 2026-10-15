import 'dart:convert';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';

/// Résultat brut de la passe post-session.
class DiarizationResult {
  const DiarizationResult({
    this.micText,
    this.speakers = const <SpeakerTurn>[],
  });
  final String? micText;
  final List<SpeakerTurn> speakers;
}

/// Service de traitement post-session (Path B) :
/// - transcrit le micro (MOI) proprement,
/// - diarize + transcrit le flux système (Interlocuteur N),
/// via un script Python (Nemotron 3 Diarization MLX + Parakeet MLX) lancé
/// avec `uv`.
class DiarizationService {
  DiarizationService();

  final Log _log = Log.named('DiarizationService');

  // Parakeet 0.6B (multilingue, MLX) : ~7x plus léger que Voxtral 4B → moins
  // de pression mémoire/GPU + timestamps par mot pour l'attribution.
  static const String _pkModel = 'mlx-community/parakeet-tdt-0.6b-v3';

  // NVIDIA Nemotron 3 Diarization (jusqu'à 8 interlocuteurs) porté en MLX.
  // Épinglé sur un commit ; archive plutôt que `git+https` pour ne pas
  // dépendre de `git` (absent sans les outils Xcode).
  static const String _diarPackage =
      'nemotron-diar-mlx @ https://github.com/9clg6/nemotron-diar-mlx/archive/'
      '71c2097309522c7191644458b4a7dcbb0b29c3b5.tar.gz';

  String get _home => Platform.environment['HOME'] ?? '/tmp';
  String get _appSupportDir =>
      '$_home/Library/Application Support/IciTranscript';
  String get _recordingsDir => '$_appSupportDir/recordings';
  String get _diarDir => '$_appSupportDir/diar';
  String get _scriptPath => '$_diarDir/process_session.py';
  // Poids Nemotron convertis en MLX (téléchargés une fois depuis Hugging Face).
  String get _diarModelCache => '$_diarDir/nemotron';
  String get _uvBin => '$_home/.local/bin/uv';

  /// Chemins WAV par session (écrits par [LiveTranscriptionService]).
  String micWavPath(String sessionId) => '$_recordingsDir/${sessionId}_mic.wav';
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
    await _removeLegacyModels();

    _log.info('Lancement passe post-session pour $sessionId');
    final ProcessResult result = await Process.run(
      _uvBin,
      <String>[
        'run',
        '--python',
        '3.12',
        '--with',
        'parakeet-mlx',
        '--with',
        _diarPackage,
        'python',
        _scriptPath,
        hasMic ? mic : '/dev/null',
        hasSys ? sys : '/dev/null',
        _pkModel,
        _diarModelCache,
      ],
      environment: <String, String>{'HOME': _home, 'PATH': _extendedPath()},
    );

    if (result.exitCode != 0) {
      _log.error(
        'Script post-session échoué (${result.exitCode}): '
        '${result.stderr}',
      );
      return null;
    }

    // La dernière ligne stdout est le JSON (les libs loggent au-dessus).
    final String out = (result.stdout as String).trim();
    final String jsonLine = out
        .split('\n')
        .lastWhere((String l) => l.trim().startsWith('{'), orElse: () => '');
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
      // Les WAV bruts sont volumineux et sensibles. Ils ne sont conservés que
      // si le traitement échoue afin de permettre une relance/diagnostic.
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

  /// Supprime les modèles sherpa-onnx (pyannote + TitaNet) des versions
  /// précédentes, remplacés par Nemotron 3 Diarization.
  Future<void> _removeLegacyModels() async {
    for (final String name in <String>['segmentation.onnx', 'embedding.onnx']) {
      await _delete('$_diarDir/$name');
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
  /// Diarization : Nemotron 3 Diarization (MLX, preset « offline » de NVIDIA,
  /// jusqu'à 8 interlocuteurs numérotés par ordre d'apparition).
  /// Transcription : Parakeet MLX (multilingue, timestamps par mot).
  /// Attribution : chaque mot va à l'interlocuteur le plus actif pendant ce
  /// mot, puis les mots consécutifs d'un même interlocuteur forment un tour.
  static const String _pyScript = r'''
import gc, json, sys, os, tempfile, wave
import numpy as np

mic_wav, sys_wav, pk_model, diar_cache = sys.argv[1:5]
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

out = {"mic_text": "", "speakers": []}
tmpd = tempfile.mkdtemp()

mic_pcm = load_pcm(mic_wav) if has(mic_wav) else np.zeros(0, dtype=np.int16)
sys_pcm = load_pcm(sys_wav) if has(sys_wav) else np.zeros(0, dtype=np.int16)

# Le micro est exclusivement « MOI ». Les interlocuteurs distants viennent du
# flux système ; diariser le micro les réintroduirait dans la mauvaise source.
src = sys_pcm if sys_pcm.size > SR and rms(sys_pcm) > 0.005 else None

# 1) Diarization avant Parakeet : un seul modèle en mémoire unifiée à la fois.
preds, frame = None, 0.01
if src is not None:
    import mlx.core as mx
    from nemotron_diar_mlx import Model
    diar = Model.from_pretrained("nvidia/Nemotron-3-Diarization", dtype=mx.bfloat16,
                                 streaming="offline", cache_dir=diar_cache)
    preds = diar(src.astype(np.float32) / 32768.0)["preds"]
    frame = diar.frame_duration
    del diar
    gc.collect()
    clear_cache = getattr(mx, "clear_cache", None) or getattr(mx.metal, "clear_cache", None)
    if clear_cache:
        clear_cache()

from parakeet_mlx import from_pretrained
m = from_pretrained(pk_model)

# 2) Transcription du micro (= MOI) pour le coach.
if mic_pcm.size > SR // 2:
    p = os.path.join(tmpd, "mic.wav"); write_wav(mic_pcm, p)
    out["mic_text"] = m.transcribe(p, chunk_duration=120.0).text.strip()

# 3) Transcription du flux système, mot par mot, attribuée aux interlocuteurs.
if preds is not None:
    from nemotron_diar_mlx import tokens_to_words, words_to_turns
    p = os.path.join(tmpd, "system.wav"); write_wav(src, p)
    result = m.transcribe(p, chunk_duration=120.0)
    words = tokens_to_words(t for s in result.sentences for t in s.tokens)
    turns = words_to_turns(words, preds, frame)
    # -1 : aucun interlocuteur détecté sur tout l'audio → un seul interlocuteur.
    out["speakers"] = [dict(t.to_dict(), speaker=max(t.speaker, 0)) for t in turns]

print(json.dumps(out, ensure_ascii=False))
''';
}
