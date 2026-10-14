"""Inférence streaming de Nemotron 3 Diarization (cache d'interlocuteurs).

Reproduit le mode synchrone de NeMo (`SortformerEncLabelModel.forward_streaming`
et `SortformerModules.streaming_update` / `_compress_spkcache`, en inférence) :

- l'audio est découpé en blocs de `chunk_len` trames d'encodeur (264 x 80 ms
  ≈ 21 s pour Nemotron 3) ;
- chaque bloc est encodé avec le cache d'interlocuteurs et la file FIFO
  devant lui, ce qui garde la numérotation des interlocuteurs cohérente d'un
  bloc à l'autre ;
- le cache est compressé à `spkcache_len` trames en gardant, par
  interlocuteur, les trames les plus représentatives.

Le coût par bloc est constant : la durée totale n'est plus limitée par la
mémoire de l'attention. La gestion du cache (petits tableaux) se fait en
NumPy ; l'encodeur tourne en MLX.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List, Optional

import mlx.core as mx
import numpy as np

from .config import ModulesConfig
from .features import IncrementalLogMel


@dataclass
class StreamingState:
    """État entre deux blocs (embeddings pré-encodés, dimension `fc_d_model`)."""

    spkcache: np.ndarray
    spkcache_preds: Optional[np.ndarray]
    fifo: np.ndarray
    fifo_preds: np.ndarray
    mean_sil_emb: np.ndarray
    n_sil_frames: int = 0
    spkcache_compressed: bool = False

    @classmethod
    def empty(cls, emb_dim: int, n_spk: int) -> "StreamingState":
        return cls(
            spkcache=np.zeros((0, emb_dim), np.float32),
            spkcache_preds=None,
            fifo=np.zeros((0, emb_dim), np.float32),
            fifo_preds=np.zeros((0, n_spk), np.float32),
            mean_sil_emb=np.zeros((emb_dim,), np.float32),
        )


# ----------------------------------------------------------------------------- mise à jour du cache


def streaming_update(
    state: StreamingState,
    chunk: np.ndarray,
    preds: np.ndarray,
    cfg: ModulesConfig,
    learnable_sil_emb: Optional[np.ndarray],
    lc: int = 0,
    rc: int = 0,
) -> np.ndarray:
    """`SortformerModules.streaming_update` (synchrone, inférence : pas de permutation).

    Args:
        chunk: embeddings pré-encodés du bloc, contextes compris `(lc + n + rc, D)`.
        preds: probabilités basse résolution de `[spkcache | fifo | bloc]`.

    Returns:
        Les probabilités du bloc (sans contexte). `state` est modifié en place.
    """
    spkcache_len, fifo_len = state.spkcache.shape[0], state.fifo.shape[0]
    chunk_len = chunk.shape[0] - lc - rc
    fifo_preds = preds[spkcache_len : spkcache_len + fifo_len]
    chunk = chunk[lc : lc + chunk_len]
    chunk_preds = preds[spkcache_len + fifo_len + lc : spkcache_len + fifo_len + lc + chunk_len]

    state.fifo = np.concatenate([state.fifo, chunk])
    state.fifo_preds = np.concatenate([fifo_preds, chunk_preds])
    if fifo_len + chunk_len > cfg.fifo_len:
        pop = max(cfg.spkcache_update_period, chunk_len - cfg.fifo_len + fifo_len)
        pop = min(pop, fifo_len + chunk_len)
        pop_embs, pop_preds = state.fifo[:pop], state.fifo_preds[:pop]
        if not cfg.use_learnable_sil_emb:
            _update_silence_profile(state, pop_embs, pop_preds, cfg.sil_threshold)
        state.fifo, state.fifo_preds = state.fifo[pop:], state.fifo_preds[pop:]
        state.spkcache = np.concatenate([state.spkcache, pop_embs])
        if state.spkcache_compressed:
            state.spkcache_preds = np.concatenate([state.spkcache_preds, pop_preds])
        else:
            # Avant la première compression, NeMo reprend les prédictions fraîches du cache.
            state.spkcache_preds = np.concatenate([preds[:spkcache_len], pop_preds])
        if state.spkcache.shape[0] > cfg.spkcache_len:
            sil_emb = learnable_sil_emb if cfg.use_learnable_sil_emb else state.mean_sil_emb
            state.spkcache, state.spkcache_preds = compress_spkcache(
                state.spkcache, state.spkcache_preds, sil_emb, cfg
            )
            state.spkcache_compressed = True
    return chunk_preds


def _update_silence_profile(state: StreamingState, embs: np.ndarray, preds: np.ndarray, threshold: float) -> None:
    is_sil = preds.sum(axis=1) < threshold
    count = int(is_sil.sum())
    if count == 0:
        return
    total = state.mean_sil_emb * state.n_sil_frames + (embs * is_sil[:, None]).sum(axis=0)
    state.n_sil_frames += count
    state.mean_sil_emb = (total / max(state.n_sil_frames, 1)).astype(np.float32)


def compress_spkcache(emb: np.ndarray, preds: np.ndarray, sil_emb: np.ndarray, cfg: ModulesConfig):
    """`SortformerModules._compress_spkcache` (inférence) : garde `spkcache_len` trames.

    Les trames retenues sont regroupées par interlocuteur (ordre d'origine
    conservé dans chaque groupe) ; `spkcache_sil_frames_per_spk` emplacements
    de silence terminent chaque groupe.

    À score strictement égal, la trame la plus ancienne est retenue. NeMo
    utilise `torch.topk`, dont le départage des ex-aequo n'est pas spécifié
    (il dépend de l'implémentation CPU/GPU) ; le reste est identique.
    """
    n_frames, n_spk = preds.shape
    per_spk = cfg.spkcache_len // n_spk - cfg.spkcache_sil_frames_per_spk
    strong = math.floor(per_spk * cfg.strong_boost_rate)
    weak = math.floor(per_spk * cfg.weak_boost_rate)
    min_pos = math.floor(per_spk * cfg.min_pos_scores_rate)

    scores = _log_pred_scores(preds, cfg.pred_score_threshold)
    scores = _disable_low_scores(preds, scores, min_pos)
    if cfg.scores_boost_latest > 0:
        scores[cfg.spkcache_len :] += np.float32(cfg.scores_boost_latest)
    _boost_topk(scores, strong, scale=2.0)
    _boost_topk(scores, weak, scale=1.0)
    if cfg.spkcache_sil_frames_per_spk > 0:
        pad = np.full((cfg.spkcache_sil_frames_per_spk, n_spk), np.inf, np.float32)
        scores = np.concatenate([scores, pad])

    # Top-k global sur les scores aplatis par interlocuteur, puis tri des indices.
    total = scores.shape[0]
    flat = scores.T.reshape(-1)
    top = _topk_indices(flat, cfg.spkcache_len, axis=0)
    top = np.where(flat[top] == -np.inf, cfg.max_index, top)
    top = np.sort(top)
    disabled = top == cfg.max_index
    top = np.remainder(top, total)
    disabled |= top >= total - cfg.spkcache_sil_frames_per_spk
    top[disabled] = 0

    new_emb = np.where(disabled[:, None], sil_emb[None, :], emb[top]).astype(np.float32)
    new_preds = np.where(disabled[:, None], 0.0, preds[top]).astype(np.float32)
    return new_emb, new_preds


def _log_pred_scores(preds: np.ndarray, threshold: float) -> np.ndarray:
    thr = np.float32(threshold)
    log_p = np.log(np.maximum(preds, thr))
    log_1p = np.log(np.maximum(np.float32(1.0) - preds, thr))
    return (log_p - log_1p + log_1p.sum(axis=1, keepdims=True) - np.float32(math.log(0.5))).astype(np.float32)


def _disable_low_scores(preds: np.ndarray, scores: np.ndarray, min_pos: int) -> np.ndarray:
    is_speech = preds > 0.5
    scores = np.where(is_speech, scores, -np.inf).astype(np.float32)
    is_pos = scores > 0
    replace = ~is_pos & is_speech & (is_pos.sum(axis=0, keepdims=True) >= min_pos)
    return np.where(replace, -np.inf, scores).astype(np.float32)


def _boost_topk(scores: np.ndarray, k: int, scale: float, offset: float = 0.5) -> None:
    if k <= 0:
        return
    idx = _topk_indices(scores, k, axis=0)  # (k, n_spk)
    cols = np.arange(scores.shape[1])[None, :]
    scores[idx, cols] -= np.float32(scale * math.log(offset))


def _topk_indices(x: np.ndarray, k: int, axis: int) -> np.ndarray:
    """Indices des `k` plus grandes valeurs ; ex-aequo départagés par indice croissant."""
    return np.take(np.argsort(-x, axis=axis, kind="stable"), np.arange(k), axis=axis)


# ----------------------------------------------------------------------------- diarisation au fil de l'eau


@dataclass
class StreamingOutput:
    """Probabilités produites par un appel : `preds` `(n, num_spks)`, `activity` `(n, 3)` ou None."""

    preds: np.ndarray
    activity: Optional[np.ndarray] = None
    start_frame: int = 0


class StreamingDiarizer:
    """Diarisation incrémentale : `feed(audio)` autant que voulu, puis `flush()`.

    Chaque appel retourne les trames finalisées depuis l'appel précédent. Les
    sorties concaténées sont identiques au `forward_streaming` de NeMo sur le
    même signal complet.
    """

    def __init__(self, model):
        self.model = model
        cfg = model.config
        self.mods = cfg.modules
        self.sub = cfg.encoder.subsampling_factor
        self.native = 1 if cfg.high_resolution else self.sub
        if cfg.output_subsampling_factor // self.native > 1:
            raise NotImplementedError("output_subsampling_factor > résolution native non supporté.")
        self.features = IncrementalLogMel(model.preprocessor_window, model.preprocessor_fb, cfg.preprocessor)
        self.state = StreamingState.empty(self.mods.fc_d_model, self.mods.num_spks)
        self._sil = (
            np.array(model.sortformer.learnable_sil_emb.astype(mx.float32))
            if self.mods.use_learnable_sil_emb
            else None
        )
        self._feats: List[np.ndarray] = []  # features en attente, à partir de `_buf_start`
        self._buf_start = 0  # indice absolu de la première trame en attente
        self._n_feats = 0  # trames de features reçues
        self._stt = 0  # début (absolu) du prochain bloc
        self._emitted = 0  # trames de sortie déjà retournées
        self._finished = False

    # -- API

    def feed(self, audio: np.ndarray) -> StreamingOutput:
        if self._finished:
            raise RuntimeError("flush() a déjà été appelé")
        self._add_features(self.features.push(audio))
        right = self.mods.chunk_right_context * self.sub
        outputs = []
        while self._n_feats - self._stt >= self.mods.chunk_len * self.sub + right:
            outputs.append(self._step(self._stt + self.mods.chunk_len * self.sub, right))
        return self._collect(outputs, limit=None)

    def flush(self) -> StreamingOutput:
        if self._finished:
            raise RuntimeError("flush() a déjà été appelé")
        self._finished = True
        self._add_features(self.features.flush())
        outputs = []
        while self._stt < self._n_feats:
            end = min(self._stt + self.mods.chunk_len * self.sub, self._n_feats)
            right = min(self.mods.chunk_right_context * self.sub, self._n_feats - end)
            outputs.append(self._step(end, right))
        total = -(-self._n_feats // self.native)
        return self._collect(outputs, limit=total)

    @property
    def frame_duration(self) -> float:
        return self.model.frame_duration

    # -- interne

    def _add_features(self, feats: mx.array) -> None:
        if feats.shape[0]:
            self._feats.append(np.array(feats))
            self._n_feats += feats.shape[0]

    def _window(self, start: int, end: int) -> np.ndarray:
        buf = np.concatenate(self._feats) if len(self._feats) > 1 else self._feats[0]
        self._feats = [buf]
        return buf[start - self._buf_start : end - self._buf_start]

    def _drop_before(self, start: int) -> None:
        if start > self._buf_start and self._feats:
            buf = self._feats[0] if len(self._feats) == 1 else np.concatenate(self._feats)
            self._feats = [buf[start - self._buf_start :]]
            self._buf_start = start

    def _step(self, end: int, right: int):
        model, mods, sub = self.model, self.mods, self.sub
        left = min(mods.chunk_left_context * sub, self._stt)
        feats = self._window(self._stt - left, end + right)
        lc, rc = round(left / sub), math.ceil(right / sub)

        chunk_embs, _ = model.encoder.pre_encode(
            mx.array(feats)[None].astype(model._dtype), mx.array([feats.shape[0]])
        )
        chunk_np = np.array(chunk_embs[0].astype(mx.float32))
        spk_n, fifo_n = self.state.spkcache.shape[0], self.state.fifo.shape[0]
        seq = np.concatenate([self.state.spkcache, self.state.fifo, chunk_np])
        emb, emb_len = model.encoder(
            mx.array(seq)[None].astype(model._dtype), mx.array([seq.shape[0]]), bypass_pre_encode=True
        )
        preds_hi, _, activity = model.forward_infer(model.sortformer.encoder_proj(emb), emb_len)
        preds_hi = np.array(preds_hi[0].astype(mx.float32))
        u = model.config.upsample_factor
        preds_lo = preds_hi.reshape(-1, u, preds_hi.shape[-1]).mean(axis=1) if u > 1 else preds_hi

        chunk_preds = streaming_update(self.state, chunk_np, preds_lo, mods, self._sil, lc, rc)
        n_chunk = chunk_np.shape[0] - lc - rc
        act = None
        if model.config.high_resolution:
            start = (spk_n + fifo_n + lc) * u
            chunk_preds = preds_hi[start : start + n_chunk * u]
            sl = slice(start, start + n_chunk * u)
        else:
            sl = slice(spk_n + fifo_n + lc, spk_n + fifo_n + lc + n_chunk)
        if activity is not None:
            logits = np.array(activity[0].astype(mx.float32))[sl]
            e = np.exp(logits - logits.max(axis=-1, keepdims=True))
            act = e / e.sum(axis=-1, keepdims=True)

        self._stt = end
        self._drop_before(self._stt - min(mods.chunk_left_context * sub, self._stt))
        return chunk_preds, act

    def _collect(self, outputs, limit: Optional[int]) -> StreamingOutput:
        n_spk = self.mods.num_spks
        preds = np.concatenate([p for p, _ in outputs]) if outputs else np.zeros((0, n_spk), np.float32)
        acts = [a for _, a in outputs if a is not None]
        act = np.concatenate(acts) if acts else None
        if limit is not None:
            keep = max(0, limit - self._emitted)
            preds = preds[:keep]
            act = act[:keep] if act is not None else None
        start = self._emitted
        self._emitted += preds.shape[0]
        if act is None and self.mods.use_activity_head:
            act = np.zeros((0, 3), np.float32)
        return StreamingOutput(preds=preds, activity=act, start_frame=start)
