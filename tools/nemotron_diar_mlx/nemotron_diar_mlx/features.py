"""Log-mel features identiques au `FilterbankFeatures` de NeMo (mode inférence).

La fenêtre de Hann et le banc de filtres mel sont repris tels quels du
checkpoint (buffers `preprocessor.featurizer.window` / `.fb`) : aucune
dépendance à librosa et aucune divergence possible sur leur construction.

`log_mel` traite un signal complet ; `IncrementalLogMel` produit exactement
les mêmes trames au fil de l'eau (audio poussé par morceaux), pour le
streaming.
"""

from __future__ import annotations

from typing import Tuple

import mlx.core as mx
import numpy as np

from .config import PreprocessorConfig


def num_feature_frames(num_samples: int, cfg: PreprocessorConfig) -> int:
    """Équivalent de `FilterbankFeatures.get_seq_len` (STFT centrée)."""
    pad = cfg.n_fft // 2 * 2
    return (num_samples + pad - cfg.n_fft) // cfg.hop_length


def _padded_window(window: mx.array, n_fft: int) -> mx.array:
    # torch.stft centre une fenêtre plus courte que n_fft.
    left = (n_fft - window.shape[0]) // 2
    return mx.pad(window.astype(mx.float32), [(left, n_fft - window.shape[0] - left)])


def _frames_log_mel(
    x: mx.array, n_frames: int, window: mx.array, mel_fb: mx.array, cfg: PreprocessorConfig
) -> mx.array:
    """Log-mel des `n_frames` trames STFT commençant au début de `x` (déjà préaccentué et paddé)."""
    if n_frames <= 0:
        return mx.zeros((0, mel_fb.shape[0]))
    idx = mx.arange(n_frames)[:, None] * cfg.hop_length + mx.arange(cfg.n_fft)[None, :]
    spec = mx.fft.rfft(x[idx] * _padded_window(window, cfg.n_fft), n=cfg.n_fft, axis=-1)
    power = mx.real(spec) ** 2 + mx.imag(spec) ** 2  # |X|^2 (mag_power = 2)
    mel = power @ mel_fb.astype(mx.float32).T
    return mx.log(mel + cfg.log_zero_guard_value)


def log_mel(
    waveform: mx.array,
    window: mx.array,
    mel_fb: mx.array,
    cfg: PreprocessorConfig,
) -> Tuple[mx.array, int]:
    """Calcule les features d'un signal mono.

    Args:
        waveform: échantillons float32 à `cfg.sample_rate`, forme `(num_samples,)`.
        window: fenêtre d'analyse `(win_length,)`.
        mel_fb: banc de filtres `(n_mels, n_fft // 2 + 1)`.

    Returns:
        Features `(num_frames, n_mels)` et le nombre de trames valides.
    """
    x = waveform.astype(mx.float32)
    valid = num_feature_frames(x.shape[0], cfg)
    # Préaccentuation (le dither n'est appliqué qu'à l'entraînement).
    x = mx.concatenate([x[:1], x[1:] - cfg.preemph * x[:-1]])
    # torch.stft(center=True, pad_mode="constant").
    half = cfg.n_fft // 2
    x = mx.pad(x, [(half, half)])
    # NeMo met à zéro les trames au-delà de seq_len puis le modèle les tronque :
    # seules les trames valides sont calculées.
    return _frames_log_mel(x, valid, window, mel_fb, cfg), valid


class IncrementalLogMel:
    """Features log-mel calculées au fil de l'eau, identiques à `log_mel`.

    La trame `f` est centrée sur l'échantillon `f * hop` : elle est émise dès
    que `n_fft / 2` échantillons suivants sont disponibles. `flush` complète
    avec le padding de fin de la STFT centrée.
    """

    def __init__(self, window: mx.array, mel_fb: mx.array, cfg: PreprocessorConfig):
        self.window = window
        self.mel_fb = mel_fb
        self.cfg = cfg
        self.half = cfg.n_fft // 2
        self.num_samples = 0
        self.next_frame = 0
        self._prev = np.float32(0.0)
        # Signal préaccentué, précédé du padding gauche ; `_start` est l'indice
        # absolu (en échantillons, padding gauche négatif) de `_buf[0]`.
        self._buf = np.zeros(self.half, dtype=np.float32)
        self._start = -self.half

    def push(self, audio: np.ndarray) -> mx.array:
        """Ajoute des échantillons et retourne les nouvelles trames `(n, n_mels)`."""
        audio = np.asarray(audio, dtype=np.float32).reshape(-1)
        if audio.size:
            shifted = np.concatenate([[self._prev], audio[:-1]]).astype(np.float32)
            self._prev = audio[-1]
            self._buf = np.concatenate([self._buf, audio - np.float32(self.cfg.preemph) * shifted])
            self.num_samples += audio.size
        ready = 0
        if self.num_samples >= self.half:
            ready = (self.num_samples - self.half) // self.cfg.hop_length + 1
        return self._emit(ready)

    def flush(self) -> mx.array:
        """Termine le signal et retourne les dernières trames."""
        self._buf = np.concatenate([self._buf, np.zeros(self.half, dtype=np.float32)])
        return self._emit(num_feature_frames(self.num_samples, self.cfg))

    def _emit(self, until: int) -> mx.array:
        n = until - self.next_frame
        if n <= 0:
            return mx.zeros((0, self.mel_fb.shape[0]))
        offset = self.next_frame * self.cfg.hop_length - self.half - self._start
        frames = _frames_log_mel(mx.array(self._buf[offset:]), n, self.window, self.mel_fb, self.cfg)
        self.next_frame = until
        # Garder uniquement les échantillons nécessaires aux trames suivantes.
        keep_from = self.next_frame * self.cfg.hop_length - self.half
        self._buf = self._buf[keep_from - self._start :]
        self._start = keep_from
        return frames
