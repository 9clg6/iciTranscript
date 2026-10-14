"""Nemotron 3 Diarization en MLX : encodeur Transformer + têtes Sortformer.

Correspondance avec NeMo :
- `TransformerEncoder`  <- `nemo.collections.asr.modules.transformer_encoder.TransformerEncoder`
  (FeatureStacking x8, LayerNorm, N blocs pré-norm RoPE/GELU, LayerNorm finale)
- `SortformerHeads`     <- `nemo.collections.asr.modules.sortformer_modules.SortformerModules`
  (encoder_proj, upsampling sub-pixel, têtes interlocuteurs et activité)
- `Model.__call__`      <- `SortformerEncLabelModel.frontend_encoder` + `forward_infer`

Seule l'inférence hors-ligne (attention complète) est implémentée ici ; le
streaming (cache d'interlocuteurs) viendra dans une étape suivante.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Optional, Tuple

import mlx.core as mx
import mlx.nn as nn

from .config import EncoderConfig, ModelConfig, ModulesConfig
from .features import log_mel


class FeatureStacking(nn.Module):
    """Empile `factor` trames consécutives puis projette vers `d_model`."""

    def __init__(self, factor: int, feat_in: int, d_model: int):
        super().__init__()
        self.factor = factor
        self.proj = nn.Linear(factor * feat_in, d_model, bias=False)

    def __call__(self, x: mx.array, lengths: mx.array) -> Tuple[mx.array, mx.array]:
        b, t, c = x.shape
        pad = (self.factor - t % self.factor) % self.factor
        if pad:
            x = mx.pad(x, [(0, 0), (0, pad), (0, 0)])
        x = x.reshape(b, (t + pad) // self.factor, c * self.factor)
        return self.proj(x), (lengths + self.factor - 1) // self.factor


class Attention(nn.Module):
    def __init__(self, cfg: EncoderConfig):
        super().__init__()
        self.n_heads = cfg.n_heads
        self.head_dim = cfg.head_dim
        self.rope_base = cfg.rope_base
        self.w_qkv = nn.Linear(cfg.d_model, 3 * cfg.d_model, bias=cfg.qkv_bias)
        self.out_proj = nn.Linear(cfg.d_model, cfg.d_model)
        if cfg.qk_norm:
            self.q_norm = nn.LayerNorm(self.head_dim)
            self.k_norm = nn.LayerNorm(self.head_dim)
        self.qk_norm = cfg.qk_norm

    def __call__(self, x: mx.array, mask: Optional[mx.array]) -> mx.array:
        b, t, d = x.shape
        qkv = self.w_qkv(x).reshape(b, t, 3, self.n_heads, self.head_dim)
        qkv = qkv.transpose(2, 0, 3, 1, 4)  # (3, B, H, T, D)
        q, k, v = qkv[0], qkv[1], qkv[2]
        if self.qk_norm:
            q = self.q_norm(q)
            k = self.k_norm(k)
        # RoPE "rotate_half" (non traditionnelle), comme RotaryPositionalEncoding.
        q = mx.fast.rope(q, self.head_dim, traditional=False, base=self.rope_base, scale=1.0, offset=0)
        k = mx.fast.rope(k, self.head_dim, traditional=False, base=self.rope_base, scale=1.0, offset=0)
        out = mx.fast.scaled_dot_product_attention(q, k, v, scale=self.head_dim**-0.5, mask=mask)
        return self.out_proj(out.transpose(0, 2, 1, 3).reshape(b, t, d))


class FeedForward(nn.Module):
    def __init__(self, cfg: EncoderConfig):
        super().__init__()
        self.fc1 = nn.Linear(cfg.d_model, cfg.ff_hidden)
        self.fc2 = nn.Linear(cfg.ff_hidden, cfg.d_model)

    def __call__(self, x: mx.array) -> mx.array:
        return self.fc2(nn.gelu(self.fc1(x)))


class TransformerBlock(nn.Module):
    def __init__(self, cfg: EncoderConfig):
        super().__init__()
        self.norm1 = nn.LayerNorm(cfg.d_model)
        self.attn = Attention(cfg)
        self.norm2 = nn.LayerNorm(cfg.d_model)
        self.ffn = FeedForward(cfg)

    def __call__(self, x: mx.array, mask: Optional[mx.array]) -> mx.array:
        x = x + self.attn(self.norm1(x), mask)
        return x + self.ffn(self.norm2(x))


class TransformerEncoder(nn.Module):
    def __init__(self, cfg: EncoderConfig):
        super().__init__()
        self.cfg = cfg
        self.pre_encode = FeatureStacking(cfg.subsampling_factor, cfg.feat_in, cfg.d_model)
        self.embed_norm = nn.LayerNorm(cfg.d_model) if cfg.pre_block_norm else None
        self.layers = [TransformerBlock(cfg) for _ in range(cfg.n_layers)]
        self.final_norm = nn.LayerNorm(cfg.d_model)

    def __call__(
        self, features: mx.array, lengths: mx.array, bypass_pre_encode: bool = False
    ) -> Tuple[mx.array, mx.array]:
        """`features` : `(B, T, feat_in)`, ou `(B, T', d_model)` si `bypass_pre_encode`."""
        if bypass_pre_encode:
            x = features
        else:
            x, lengths = self.pre_encode(features, lengths)
        if self.cfg.xscaling:
            x = x * (self.cfg.d_model**0.5)
        if self.embed_norm is not None:
            x = self.embed_norm(x)
        mask = _key_padding_mask(lengths, x.shape[1])
        for layer in self.layers:
            x = layer(x, mask)
        return self.final_norm(x), lengths


class SortformerHeads(nn.Module):
    def __init__(self, cfg: ModulesConfig, upsample_factor: int):
        super().__init__()
        self.upsample_factor = upsample_factor
        h = cfg.tf_d_model
        self.encoder_proj = nn.Linear(cfg.fc_d_model, h)
        if upsample_factor > 1:
            self.subpixel_upsample = nn.Conv1d(h, h * upsample_factor, kernel_size=3, padding=1)
        self.first_hidden_to_hidden = nn.Linear(h, h)
        self.single_hidden_to_spks = nn.Linear(h, cfg.num_spks)
        if cfg.use_activity_head:
            self.activity_norm = nn.LayerNorm(h)
            self.activity_proj = nn.Linear(h, 3)
        if cfg.use_learnable_sil_emb:
            # Utilisé par le cache d'interlocuteurs en streaming.
            self.learnable_sil_emb = mx.zeros((cfg.fc_d_model,))
        self.use_activity_head = cfg.use_activity_head

    def upsample(self, x: mx.array) -> mx.array:
        if self.upsample_factor == 1:
            return x
        b, t, h = x.shape
        y = self.subpixel_upsample(x)  # (B, T, H * u), canal = u_idx * H + h
        return y.reshape(b, t * self.upsample_factor, h)

    def speaker_logits(self, x: mx.array) -> mx.array:
        x = self.first_hidden_to_hidden(nn.relu(x))
        return self.single_hidden_to_spks(nn.relu(x))

    def activity_logits(self, x: mx.array) -> Optional[mx.array]:
        if not self.use_activity_head:
            return None
        return self.activity_proj(self.activity_norm(x))


class Model(nn.Module):
    def __init__(self, config: ModelConfig):
        super().__init__()
        self.config = config
        pre = config.preprocessor
        self.encoder = TransformerEncoder(config.encoder)
        self.sortformer = SortformerHeads(config.modules, config.upsample_factor)
        # Buffers du préprocesseur NeMo, chargés depuis les poids convertis.
        self.preprocessor_window = mx.zeros((pre.win_length,))
        self.preprocessor_fb = mx.zeros((pre.features, pre.n_fft // 2 + 1))

    # ------------------------------------------------------------------ chargement

    @classmethod
    def from_pretrained(cls, path: str | Path, dtype: mx.Dtype = mx.float32) -> "Model":
        path = Path(path)
        config = ModelConfig.from_dict(json.loads((path / "config.json").read_text()))
        model = cls(config)
        weights = mx.load(str(path / "model.safetensors"))
        model.load_weights(list(weights.items()), strict=True)
        if dtype != mx.float32:
            # Les buffers du préprocesseur restent en float32.
            model.encoder.set_dtype(dtype)
            model.sortformer.set_dtype(dtype)
        mx.eval(model.parameters())
        model.eval()
        return model

    # ------------------------------------------------------------------ inférence

    def features(self, waveform: mx.array) -> Tuple[mx.array, int]:
        """Features `(T, n_mels)` d'un signal mono, normalisé comme `process_signal`."""
        if not self.config.streaming_mode:
            waveform = waveform / (mx.max(waveform) + self.config.eps)
        return log_mel(waveform, self.preprocessor_window, self.preprocessor_fb, self.config.preprocessor)

    def encode(self, features: mx.array, lengths: mx.array) -> Tuple[mx.array, mx.array]:
        """`frontend_encoder` : features `(B, T, n_mels)` -> embeddings `(B, T/8, tf_d_model)`."""
        emb, emb_lengths = self.encoder(features.astype(self._dtype), lengths)
        return self.sortformer.encoder_proj(emb), emb_lengths

    def forward_infer(
        self, emb: mx.array, emb_lengths: mx.array
    ) -> Tuple[mx.array, mx.array, Optional[mx.array]]:
        """Probabilités `(B, T*u, num_spks)`, logits et logits d'activité."""
        hidden = self.sortformer.upsample(emb)
        mask = _length_mask(emb_lengths * self.config.upsample_factor, hidden.shape[1])
        logits = self.sortformer.speaker_logits(hidden)
        preds = mx.sigmoid(logits) * mask[..., None]
        return preds, logits, self.sortformer.activity_logits(hidden)

    def __call__(self, waveform: mx.array) -> Dict[str, mx.array]:
        """Diarisation hors-ligne d'un signal mono 16 kHz.

        Retourne `preds` `(T_out, num_spks)` : probabilité d'activité de chaque
        interlocuteur toutes les `frame_duration` secondes, et `activity`
        `(T_out, 3)` (silence / une voix / chevauchement) si la tête existe.
        L'attention est quadratique en durée : réservé aux enregistrements
        courts tant que le mode streaming n'est pas porté.
        """
        feats, n_valid = self.features(waveform)
        lengths = mx.array([n_valid])
        emb, emb_lengths = self.encode(feats[None], lengths)
        preds, _, activity = self.forward_infer(emb, emb_lengths)

        frame_factor = 1 if self.config.high_resolution else self.config.encoder.subsampling_factor
        n_out = min(preds.shape[1], -(-n_valid // frame_factor))
        out = {"preds": preds[0, :n_out].astype(mx.float32)}
        if activity is not None:
            out["activity"] = mx.softmax(activity[0, :n_out].astype(mx.float32), axis=-1)
        downsample = self.config.output_subsampling_factor // frame_factor
        if downsample > 1:
            raise NotImplementedError("output_subsampling_factor > résolution native non supporté.")
        return out

    @property
    def frame_duration(self) -> float:
        """Durée (s) d'une trame de sortie."""
        return self.config.output_subsampling_factor * self.config.preprocessor.window_stride

    @property
    def _dtype(self) -> mx.Dtype:
        return self.sortformer.encoder_proj.weight.dtype


def _length_mask(lengths: mx.array, max_len: int) -> mx.array:
    return (mx.arange(max_len)[None, :] < lengths[:, None]).astype(mx.float32)


def _key_padding_mask(lengths: mx.array, max_len: int) -> Optional[mx.array]:
    """Masque booléen `(B, 1, 1, T)` sur les clés ; `None` si aucune trame paddée."""
    if lengths.shape[0] == 1 and int(lengths[0]) == max_len:
        return None
    return (mx.arange(max_len)[None, :] < lengths[:, None])[:, None, None, :]
