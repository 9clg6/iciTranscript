"""Log-mel features identiques au `FilterbankFeatures` de NeMo (mode inférence).

La fenêtre de Hann et le banc de filtres mel sont repris tels quels du
checkpoint (buffers `preprocessor.featurizer.window` / `.fb`) : aucune
dépendance à librosa et aucune divergence possible sur leur construction.
"""

from __future__ import annotations

from typing import Tuple

import mlx.core as mx

from .config import PreprocessorConfig


def num_feature_frames(num_samples: int, cfg: PreprocessorConfig) -> int:
    """Équivalent de `FilterbankFeatures.get_seq_len` (STFT centrée)."""
    pad = cfg.n_fft // 2 * 2
    return (num_samples + pad - cfg.n_fft) // cfg.hop_length


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
    n = x.shape[0]
    valid = num_feature_frames(n, cfg)

    # Préaccentuation (le dither n'est appliqué qu'à l'entraînement).
    x = mx.concatenate([x[:1], x[1:] - cfg.preemph * x[:-1]])

    # torch.stft(center=True, pad_mode="constant") avec une fenêtre plus courte
    # que n_fft : la fenêtre est centrée dans n_fft.
    half = cfg.n_fft // 2
    x = mx.pad(x, [(half, half)])
    left = (cfg.n_fft - window.shape[0]) // 2
    win = mx.pad(window.astype(mx.float32), [(left, cfg.n_fft - window.shape[0] - left)])

    n_frames = 1 + (x.shape[0] - cfg.n_fft) // cfg.hop_length
    idx = mx.arange(n_frames)[:, None] * cfg.hop_length + mx.arange(cfg.n_fft)[None, :]
    frames = x[idx] * win
    spec = mx.fft.rfft(frames, n=cfg.n_fft, axis=-1)
    power = mx.real(spec) ** 2 + mx.imag(spec) ** 2  # |X|^2 (mag_power = 2)

    mel = power @ mel_fb.astype(mx.float32).T
    mel = mx.log(mel + cfg.log_zero_guard_value)
    # NeMo met à zéro (pad_value) les trames au-delà de seq_len puis le modèle
    # tronque à seq_len : on ne garde que les trames valides.
    return mel[:valid], valid
