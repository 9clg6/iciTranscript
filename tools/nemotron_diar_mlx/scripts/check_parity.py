"""Compare le portage MLX à NeMo (PyTorch) sur le même `.nemo`.

    python scripts/check_parity.py model.nemo [audio.wav] [--seconds 20]

Convertit le checkpoint dans un dossier temporaire, puis compare étape par
étape : features mel, sortie de l'encodeur, probabilités par interlocuteur et
logits d'activité (chemin hors-ligne `frontend_encoder` + `forward_infer`).
Sans fichier audio, un signal synthétique (voix simulées + bruit) est utilisé.
Code de sortie non nul si un écart dépasse la tolérance.
"""

import argparse
import sys
import tempfile

import mlx.core as mx
import numpy as np
import torch
from nemo.collections.asr.models import SortformerEncLabelModel

from nemotron_diar_mlx.convert import convert
from nemotron_diar_mlx.model import Model


def synthetic_audio(seconds: float, sr: int = 16000) -> np.ndarray:
    rng = np.random.default_rng(0)
    t = np.arange(int(seconds * sr)) / sr
    audio = 0.01 * rng.standard_normal(t.shape)
    # Plusieurs « locuteurs » : harmoniques à f0 différentes, alternées et parfois superposées.
    for i, f0 in enumerate((110.0, 180.0, 240.0)):
        gate = (np.sin(2 * np.pi * (0.2 + 0.07 * i) * t + i) > 0.2).astype(np.float64)
        voice = sum(np.sin(2 * np.pi * f0 * k * t) / k for k in range(1, 6))
        audio += 0.2 * gate * voice * (1 + 0.3 * np.sin(2 * np.pi * 3 * t))
    return audio.astype(np.float32)


def load_audio(path: str, sr: int) -> np.ndarray:
    import soundfile as sf

    audio, file_sr = sf.read(path, dtype="float32", always_2d=True)
    if file_sr != sr:
        raise SystemExit(f"{path}: {file_sr} Hz, rééchantillonner à {sr} Hz d'abord")
    return audio.mean(axis=1)


def report(name: str, ref: np.ndarray, got: np.ndarray, atol: float) -> bool:
    if ref.shape != got.shape:
        print(f"[ÉCHEC] {name}: formes {ref.shape} (NeMo) != {got.shape} (MLX)")
        return False
    diff = np.abs(ref.astype(np.float64) - got.astype(np.float64))
    scale = np.abs(ref).max() + 1e-12
    ok = diff.max() <= atol
    print(
        f"[{'OK' if ok else 'ÉCHEC'}] {name:<18} forme={ref.shape} "
        f"écart max={diff.max():.3e} moyen={diff.mean():.3e} (échelle {scale:.3e}, tolérance {atol:.0e})"
    )
    return ok


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("nemo")
    parser.add_argument("audio", nargs="?")
    parser.add_argument("--seconds", type=float, default=20.0)
    args = parser.parse_args()

    ref_model = SortformerEncLabelModel.restore_from(args.nemo, map_location="cpu")
    ref_model.eval()
    sr = ref_model.cfg.sample_rate
    audio = load_audio(args.audio, sr) if args.audio else synthetic_audio(args.seconds, sr)

    with tempfile.TemporaryDirectory() as tmp:
        convert(args.nemo, tmp)
        mlx_model = Model.from_pretrained(tmp)

    ok = True
    with torch.no_grad():
        signal = torch.from_numpy(audio)[None]
        length = torch.tensor([signal.shape[1]])
        ref_feats, ref_len = ref_model.process_signal(audio_signal=signal, audio_signal_length=length)
        ref_feats = ref_feats[:, :, : ref_len.max()]
        ref_emb, ref_emb_len = ref_model.frontend_encoder(ref_feats, ref_len)
        ref_preds, ref_logits, ref_activity = ref_model.forward_infer(ref_emb, ref_emb_len, return_logits=True)

    feats, n_valid = mlx_model.features(mx.array(audio))
    ok &= report("features mel", ref_feats[0].T.numpy(), np.array(feats), atol=1e-3)

    # Encodeur alimenté par les features NeMo pour isoler ses propres écarts.
    emb, emb_len = mlx_model.encode(mx.array(ref_feats.transpose(1, 2).numpy()), mx.array(ref_len.numpy()))
    ok &= report("sortie encodeur", ref_emb.numpy(), np.array(emb), atol=5e-3)
    preds, logits, activity = mlx_model.forward_infer(emb, emb_len)
    ok &= report("logits locuteurs", ref_logits.numpy(), np.array(logits), atol=5e-3)
    ok &= report("probas locuteurs", ref_preds.numpy(), np.array(preds), atol=1e-3)
    if ref_activity is not None:
        ok &= report("logits activité", ref_activity.numpy(), np.array(activity), atol=5e-3)

    # Chaîne complète MLX (audio -> probabilités) contre NeMo.
    out = mlx_model(mx.array(audio))
    full = np.array(out["preds"])
    ok &= report("bout en bout", ref_preds[0, : full.shape[0]].numpy(), full, atol=2e-3)
    print(f"{full.shape[0]} trames de {mlx_model.frame_duration * 1000:.0f} ms, {full.shape[1]} interlocuteurs")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
