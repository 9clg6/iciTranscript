"""Conversion d'un checkpoint NeMo `.nemo` de Nemotron 3 Diarization vers MLX.

Usage :
    python -m nemotron_diar_mlx.convert Nemotron-3-Diarization.nemo out_dir [--dtype bfloat16]

Produit `out_dir/config.json` et `out_dir/model.safetensors`, chargeables avec
`Model.from_pretrained(out_dir)`. Nécessite `torch` (lecture du checkpoint) et
`pyyaml`, uniquement pour la conversion.
"""

from __future__ import annotations

import argparse
import json
import re
import tarfile
from pathlib import Path
from typing import Dict, Iterable, Tuple

import mlx.core as mx
import numpy as np
import yaml

from .config import ModelConfig

# Paramètres présents dans le checkpoint mais inutilisés à l'inférence.
_IGNORED = (
    re.compile(r"^sortformer_modules\.hidden_to_spks\."),  # tête historique, gelée et non appelée
)

# (motif NeMo, remplacement MLX)
_RENAMES: Tuple[Tuple[re.Pattern, str], ...] = tuple(
    (re.compile(p), r)
    for p, r in (
        (r"^preprocessor\.featurizer\.window$", "preprocessor_window"),
        (r"^preprocessor\.featurizer\.fb$", "preprocessor_fb"),
        (r"^encoder\.layers\.(\d+)\.ffn\.net\.0\.", r"encoder.layers.\1.ffn.fc1."),
        (r"^encoder\.layers\.(\d+)\.ffn\.net\.3\.", r"encoder.layers.\1.ffn.fc2."),
        (r"^encoder\.", "encoder."),
        (r"^sortformer_modules\.activity_head\.0\.", "sortformer.activity_norm."),
        (r"^sortformer_modules\.activity_head\.1\.", "sortformer.activity_proj."),
        (r"^sortformer_modules\.", "sortformer."),
    )
)


def read_nemo(path: str | Path) -> Tuple[dict, Dict[str, np.ndarray]]:
    """Lit `model_config.yaml` et `model_weights.ckpt` depuis une archive `.nemo`."""
    import torch  # dépendance de conversion uniquement

    with tarfile.open(path, "r:*") as tar:
        members = {Path(m.name).name: m for m in tar.getmembers() if m.isfile()}
        for required in ("model_config.yaml", "model_weights.ckpt"):
            if required not in members:
                raise ValueError(f"{path}: {required} introuvable dans l'archive .nemo")
        config = yaml.safe_load(tar.extractfile(members["model_config.yaml"]).read())
        state = torch.load(
            tar.extractfile(members["model_weights.ckpt"]), map_location="cpu", weights_only=True
        )
    if "state_dict" in state:
        state = state["state_dict"]
    return config, {k: v.detach().to(torch.float32).numpy() for k, v in state.items()}


def map_weights(state: Dict[str, np.ndarray]) -> Dict[str, np.ndarray]:
    """Renomme et réordonne les tenseurs NeMo pour le module MLX."""
    out: Dict[str, np.ndarray] = {}
    unknown = []
    for name, value in state.items():
        if any(p.search(name) for p in _IGNORED):
            continue
        new = None
        for pattern, repl in _RENAMES:
            if pattern.search(name):
                new = pattern.sub(repl, name, count=1)
                break
        if new is None:
            unknown.append(name)
            continue
        if new == "preprocessor_fb":
            value = value.reshape(value.shape[-2], value.shape[-1])  # (1, n_mels, F) -> (n_mels, F)
        elif new == "sortformer.subpixel_upsample.weight":
            value = value.transpose(0, 2, 1)  # Conv1d PyTorch (O, I, K) -> MLX (O, K, I)
        out[new] = value
    if unknown:
        raise ValueError("Tenseurs NeMo non reconnus (architecture inattendue ?) :\n  " + "\n  ".join(unknown))
    return out


def convert(nemo_path: str | Path, out_dir: str | Path, dtype: str = "float32") -> Path:
    config_dict, state = read_nemo(nemo_path)
    config = ModelConfig.from_nemo_config(config_dict)
    weights = map_weights(state)
    _check_against_model(config, weights)

    target = getattr(mx, dtype)
    arrays = {
        k: mx.array(v) if k.startswith("preprocessor_") else mx.array(v).astype(target)
        for k, v in weights.items()
    }
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    mx.save_safetensors(str(out_dir / "model.safetensors"), arrays, metadata={"format": "mlx"})
    (out_dir / "config.json").write_text(json.dumps(config.to_dict(), indent=2) + "\n")
    return out_dir


def _check_against_model(config: ModelConfig, weights: Dict[str, np.ndarray]) -> None:
    """Vérifie que noms et formes correspondent exactement au module MLX."""
    from mlx.utils import tree_flatten

    from .model import Model

    expected = dict(tree_flatten(Model(config).parameters()))
    missing = sorted(set(expected) - set(weights))
    extra = sorted(set(weights) - set(expected))
    bad_shapes = [
        f"{k}: checkpoint {weights[k].shape} != modèle {tuple(expected[k].shape)}"
        for k in sorted(set(expected) & set(weights))
        if tuple(weights[k].shape) != tuple(expected[k].shape)
    ]
    problems = _section("manquants", missing) + _section("en trop", extra) + _section("formes", bad_shapes)
    if problems:
        raise ValueError("Poids incompatibles avec le modèle MLX :" + problems)


def _section(title: str, items: Iterable[str]) -> str:
    items = list(items)
    return f"\n {title}:\n  " + "\n  ".join(items) if items else ""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("nemo", help="Chemin du fichier .nemo")
    parser.add_argument("out_dir", help="Dossier de sortie MLX")
    parser.add_argument("--dtype", default="float32", choices=("float32", "float16", "bfloat16"))
    args = parser.parse_args()
    out = convert(args.nemo, args.out_dir, args.dtype)
    print(f"Modèle MLX écrit dans {out}")


if __name__ == "__main__":
    main()
