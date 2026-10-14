"""Configuration du portage MLX de Nemotron 3 Diarization.

Les valeurs par défaut reproduisent `sortformer_streaming_8spk.yaml` de NeMo,
documenté comme configuration d'entraînement de Nemotron-3-Diarization.
`ModelConfig.from_nemo_config` lit le `model_config.yaml` embarqué dans un
fichier `.nemo` et refuse les architectures non supportées (ex. Sortformer
v2.x à encodeur FastConformer).
"""

from __future__ import annotations

import dataclasses
from dataclasses import dataclass, field
from typing import Any, Dict


@dataclass
class PreprocessorConfig:
    sample_rate: int = 16000
    window_size: float = 0.025
    window_stride: float = 0.01
    n_fft: int = 512
    features: int = 128
    preemph: float = 0.97
    log_zero_guard_value: float = 2**-24

    @property
    def win_length(self) -> int:
        return int(self.window_size * self.sample_rate)

    @property
    def hop_length(self) -> int:
        return int(self.window_stride * self.sample_rate)


@dataclass
class EncoderConfig:
    feat_in: int = 128
    d_model: int = 512
    n_heads: int = 8
    n_layers: int = 31
    subsampling_factor: int = 8
    ff_expansion: float = 4.0
    qkv_bias: bool = False
    qk_norm: bool = False
    pre_block_norm: bool = True
    rope_base: float = 10000.0
    xscaling: bool = False

    @property
    def head_dim(self) -> int:
        return self.d_model // self.n_heads

    @property
    def ff_hidden(self) -> int:
        return int(self.ff_expansion * self.d_model)


@dataclass
class ModulesConfig:
    num_spks: int = 8
    fc_d_model: int = 512
    tf_d_model: int = 192
    use_activity_head: bool = True
    use_learnable_sil_emb: bool = True
    # Paramètres de streaming, conservés pour l'étape suivante du portage.
    spkcache_len: int = 264
    fifo_len: int = 0
    chunk_len: int = 264
    spkcache_update_period: int = 264
    chunk_left_context: int = 0
    chunk_right_context: int = 0
    spkcache_sil_frames_per_spk: int = 1
    pred_score_threshold: float = 0.25
    max_index: int = 99999
    scores_boost_latest: float = 0.05
    sil_threshold: float = 0.2
    strong_boost_rate: float = 0.75
    weak_boost_rate: float = 1.5
    min_pos_scores_rate: float = 0.5


@dataclass
class ModelConfig:
    preprocessor: PreprocessorConfig = field(default_factory=PreprocessorConfig)
    encoder: EncoderConfig = field(default_factory=EncoderConfig)
    modules: ModulesConfig = field(default_factory=ModulesConfig)
    high_resolution: bool = True
    output_subsampling_factor: int = 1
    streaming_mode: bool = True
    eps: float = 1e-3

    @property
    def upsample_factor(self) -> int:
        return self.encoder.subsampling_factor if self.high_resolution else 1

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ModelConfig":
        return cls(
            preprocessor=_build(PreprocessorConfig, d.get("preprocessor", {})),
            encoder=_build(EncoderConfig, d.get("encoder", {})),
            modules=_build(ModulesConfig, d.get("modules", {})),
            **{k: v for k, v in d.items() if k not in ("preprocessor", "encoder", "modules")},
        )

    @classmethod
    def from_nemo_config(cls, cfg: Dict[str, Any]) -> "ModelConfig":
        """Construit la config depuis le `model_config.yaml` d'un `.nemo` (déjà résolu)."""
        enc = cfg["encoder"]
        target = enc.get("_target_", "")
        if not target.endswith(".TransformerEncoder") or "transformer_encoders" in target:
            raise ValueError(
                f"Encodeur non supporté: {target!r}. Ce portage vise Nemotron 3 Diarization "
                "(nemo.collections.asr.modules.TransformerEncoder)."
            )
        if cfg.get("transformer_encoder") is not None:
            raise ValueError("Un `transformer_encoder` séparé n'est pas supporté par ce portage.")
        _expect(enc, "subsampling", "feature_stacking")
        _expect(enc, "self_attention_model", "rope")
        _expect(enc, "attn_mode", "full")
        if float(enc.get("rotary_fraction", 1.0)) != 1.0:
            raise ValueError("rotary_fraction != 1.0 non supporté.")
        if enc.get("feat_out", -1) not in (-1, None, enc["d_model"]):
            raise ValueError("feat_out (projection de sortie de l'encodeur) non supporté.")

        pre = cfg["preprocessor"]
        _expect(pre, "normalize", "NA")
        _expect(pre, "frame_splicing", 1)
        _expect(pre, "window", "hann")
        for key, expected in (("log", True), ("mag_power", 2.0), ("exact_pad", False)):
            if pre.get(key, expected) != expected:
                raise ValueError(f"preprocessor.{key}={pre.get(key)!r} non supporté (attendu {expected!r}).")

        # Les valeurs par défaut reprennent celles du constructeur
        # `SortformerModules`, utilisées quand la config ne les précise pas.
        mods = cfg["sortformer_modules"]
        num_spks = int(cfg.get("max_num_of_spks", mods.get("num_spks", 4)))
        high_resolution = bool(cfg.get("high_resolution", False))
        subsampling = int(enc["subsampling_factor"])
        out_factor = cfg.get("output_subsampling_factor", subsampling)
        if isinstance(out_factor, str):  # interpolation non résolue `${...}`
            out_factor = subsampling

        return cls(
            preprocessor=PreprocessorConfig(
                sample_rate=int(pre.get("sample_rate", 16000)),
                window_size=float(pre.get("window_size", 0.025)),
                window_stride=float(pre.get("window_stride", 0.01)),
                n_fft=int(pre.get("n_fft", 512)),
                features=int(pre.get("features", 128)),
                preemph=float(pre.get("preemph", 0.97)),
                log_zero_guard_value=float(pre.get("log_zero_guard_value", 2**-24)),
            ),
            encoder=EncoderConfig(
                feat_in=int(enc.get("feat_in", pre.get("features", 128))),
                d_model=int(enc["d_model"]),
                n_heads=int(enc["n_heads"]),
                n_layers=int(enc["n_layers"]),
                subsampling_factor=subsampling,
                ff_expansion=float(enc.get("ff_expansion", 4.0)),
                qkv_bias=bool(enc.get("qkv_bias", False)),
                qk_norm=bool(enc.get("qk_norm", False)),
                pre_block_norm=bool(enc.get("pre_block_norm", True)),
                rope_base=float(enc.get("rope_base", 10000.0)),
                xscaling=bool(enc.get("xscaling", False)),
            ),
            modules=ModulesConfig(
                num_spks=num_spks,
                fc_d_model=int(mods["fc_d_model"]),
                tf_d_model=int(mods["tf_d_model"]),
                use_activity_head=float(cfg.get("activity_weight", 0.0)) > 0.0,
                use_learnable_sil_emb=bool(mods.get("use_learnable_sil_emb", False)),
                spkcache_len=int(mods.get("spkcache_len", 188)),
                fifo_len=int(mods.get("fifo_len", 0)),
                chunk_len=int(mods.get("chunk_len", 188)),
                spkcache_update_period=int(mods.get("spkcache_update_period", 188)),
                chunk_left_context=int(mods.get("chunk_left_context", 1)),
                chunk_right_context=int(mods.get("chunk_right_context", 1)),
                spkcache_sil_frames_per_spk=int(mods.get("spkcache_sil_frames_per_spk", 3)),
                pred_score_threshold=float(mods.get("pred_score_threshold", 0.25)),
                max_index=int(mods.get("max_index", 99999)),
                scores_boost_latest=float(mods.get("scores_boost_latest", 0.05)),
                sil_threshold=float(mods.get("sil_threshold", 0.2)),
                strong_boost_rate=float(mods.get("strong_boost_rate", 0.75)),
                weak_boost_rate=float(mods.get("weak_boost_rate", 1.5)),
                min_pos_scores_rate=float(mods.get("min_pos_scores_rate", 0.5)),
            ),
            high_resolution=high_resolution,
            output_subsampling_factor=int(out_factor),
            streaming_mode=bool(cfg.get("streaming_mode", False)),
            eps=float(cfg.get("eps", 1e-3)),
        )


def _build(klass, values: Dict[str, Any]):
    names = {f.name for f in dataclasses.fields(klass)}
    return klass(**{k: v for k, v in values.items() if k in names})


def _expect(section: Dict[str, Any], key: str, expected: Any) -> None:
    value = section.get(key, expected)
    if value != expected:
        raise ValueError(f"{key}={value!r} non supporté (attendu {expected!r}).")
