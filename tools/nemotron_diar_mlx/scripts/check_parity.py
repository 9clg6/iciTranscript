"""Compare le portage MLX à NeMo (PyTorch) sur le même `.nemo`.

    python scripts/check_parity.py model.nemo [audio.wav] [--seconds 20]

Convertit le checkpoint dans un dossier temporaire, puis compare :
- hors-ligne, étape par étape : features mel, sortie de l'encodeur,
  probabilités par interlocuteur, logits d'activité ;
- la compression du cache d'interlocuteurs et l'état streaming complet
  (cache, FIFO, prédictions) bloc après bloc, sur des entrées aléatoires ;
- le streaming contre `forward_streaming` : en mode guidé (chaque bloc
  repart de l'état NeMo, tolérance stricte) et en mode libre (audio poussé par
  morceaux irréguliers ; un ex-aequo de sélection du cache peut y être
  départagé différemment par l'arrondi flottant), plus les features
  incrémentales.
Sans fichier audio, un signal synthétique (voix simulées + bruit) est utilisé.
Code de sortie non nul si un écart dépasse la tolérance.
"""

import argparse
import contextlib
import copy
import sys
import tempfile

import mlx.core as mx
import numpy as np
import torch
from nemo.collections.asr.models import SortformerEncLabelModel

from nemotron_diar_mlx.convert import convert
from nemotron_diar_mlx.features import IncrementalLogMel, log_mel
from nemotron_diar_mlx.model import Model
from nemotron_diar_mlx.streaming import StreamingDiarizer, StreamingState, compress_spkcache, streaming_update


@contextlib.contextmanager
def stable_topk():
    """Fait départager les ex-aequo de `torch.topk` par indice croissant, comme le portage.

    `torch.topk` ne spécifie pas quel élément garder entre valeurs égales ;
    la compression du cache en rencontre (trames identiques, prédictions
    saturées). On fixe la même règle des deux côtés pour comparer le reste.
    """
    original = torch.topk

    def topk(x, k, dim=-1, largest=True, sorted=True, **kwargs):
        if not largest:
            return original(x, k, dim=dim, largest=largest, sorted=sorted, **kwargs)
        values, indices = torch.sort(x, dim=dim, descending=True, stable=True)
        return torch.return_types.topk((values.narrow(dim, 0, k), indices.narrow(dim, 0, k)))

    torch.topk = topk
    try:
        yield
    finally:
        torch.topk = original


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


def check_offline(ref_model, mlx_model, audio: np.ndarray) -> bool:
    """Chemin hors-ligne : `frontend_encoder` + `forward_infer` sur tout le signal."""
    print("== Hors-ligne (attention complète)")
    ok = True
    with torch.no_grad():
        signal = torch.from_numpy(audio)[None]
        length = torch.tensor([signal.shape[1]])
        ref_feats, ref_len = ref_model.process_signal(audio_signal=signal, audio_signal_length=length)
        ref_feats = ref_feats[:, :, : ref_len.max()]
        ref_emb, ref_emb_len = ref_model.frontend_encoder(ref_feats, ref_len)
        ref_preds, ref_logits, ref_activity = ref_model.forward_infer(ref_emb, ref_emb_len, return_logits=True)

    feats, _ = mlx_model.features(mx.array(audio))
    ok &= report("features mel", ref_feats[0].T.numpy(), np.array(feats), atol=1e-3)

    # Encodeur alimenté par les features NeMo pour isoler ses propres écarts.
    emb, emb_len = mlx_model.encode(mx.array(ref_feats.transpose(1, 2).numpy()), mx.array(ref_len.numpy()))
    ok &= report("sortie encodeur", ref_emb.numpy(), np.array(emb), atol=1e-3)
    preds, logits, activity = mlx_model.forward_infer(emb, emb_len)
    ok &= report("logits locuteurs", ref_logits.numpy(), np.array(logits), atol=1e-3)
    ok &= report("probas locuteurs", ref_preds.numpy(), np.array(preds), atol=1e-4)
    if ref_activity is not None:
        ok &= report("logits activité", ref_activity.numpy(), np.array(activity), atol=1e-3)

    full = mlx_model.forward_offline(audio)["preds"]
    ok &= report("bout en bout", ref_preds[0, : full.shape[0]].numpy(), full, atol=1e-4)
    return ok


def check_compression(ref_model, mlx_model, trials: int = 20) -> bool:
    """`compress_spkcache` contre `SortformerModules._compress_spkcache` sur entrées aléatoires."""
    print("== Compression du cache d'interlocuteurs")
    mods = ref_model.sortformer_modules
    cfg = mlx_model.config.modules
    sil = np.array(mlx_model.sortformer.learnable_sil_emb) if cfg.use_learnable_sil_emb else None
    rng = np.random.default_rng(1)
    ok = True
    for trial in range(trials):
        n = cfg.spkcache_len + int(rng.integers(1, cfg.chunk_len + 1))
        # Mélange de silences, de locuteurs isolés et de chevauchements.
        logits = rng.normal(-2.0, 2.5, size=(n, cfg.num_spks)).astype(np.float32)
        active = rng.integers(0, cfg.num_spks, size=n)
        logits[np.arange(n), active] += rng.uniform(0, 6, size=n).astype(np.float32)
        preds = 1 / (1 + np.exp(-logits))
        emb = rng.standard_normal((n, cfg.fc_d_model)).astype(np.float32)
        if trial % 2:
            # Trames dupliquées (ex. silence numérique) : scores strictement égaux
            # dans les deux implémentations, départagés par la règle d'ex-aequo.
            src = rng.integers(0, n, size=n // 3)
            dst = rng.choice(n, size=n // 3, replace=False)
            preds[dst], emb[dst] = preds[src], emb[src]
        mean_sil = rng.standard_normal(cfg.fc_d_model).astype(np.float32)
        with torch.no_grad(), stable_topk():
            ref_emb, ref_preds, _ = mods._compress_spkcache(
                torch.from_numpy(emb)[None], torch.from_numpy(preds)[None], torch.from_numpy(mean_sil)[None]
            )
        got_emb, got_preds = compress_spkcache(emb, preds, sil if sil is not None else mean_sil, cfg)
        same = np.array_equal(ref_emb[0].numpy(), got_emb) and np.array_equal(ref_preds[0].numpy(), got_preds)
        if not same:
            print(f"[ÉCHEC] essai {trial}: cache compressé différent (n={n})")
        ok &= same
    if ok:
        print(f"[OK] {trials} essais aléatoires (dont {trials // 2} avec ex-aequo) : cache identique bit à bit")
    return ok


def check_streaming_update(ref_model, mlx_model, steps: int = 6) -> bool:
    """État complet (cache, FIFO, prédictions) après chaque `streaming_update`, contre NeMo."""
    print("== Mise à jour de l'état streaming")
    mods = ref_model.sortformer_modules
    cfg = mlx_model.config.modules
    sil = np.array(mlx_model.sortformer.learnable_sil_emb) if cfg.use_learnable_sil_emb else None
    rng = np.random.default_rng(3)
    ref_state = mods.init_streaming_state(batch_size=1, device="cpu")
    state = StreamingState.empty(cfg.fc_d_model, cfg.num_spks)
    ok = True
    for step in range(steps):
        n_chunk = cfg.chunk_len if step < steps - 1 else int(rng.integers(1, cfg.chunk_len))
        total = state.spkcache.shape[0] + state.fifo.shape[0] + n_chunk
        logits = rng.normal(-2.0, 2.5, size=(total, cfg.num_spks)).astype(np.float32)
        logits[np.arange(total), rng.integers(0, cfg.num_spks, size=total)] += 5.0
        preds = 1 / (1 + np.exp(-logits))
        chunk = rng.standard_normal((n_chunk, cfg.fc_d_model)).astype(np.float32)
        with torch.no_grad(), stable_topk():
            ref_state, ref_chunk_preds = mods.streaming_update(
                ref_state, torch.from_numpy(chunk)[None], torch.from_numpy(preds)[None]
            )
        chunk_preds = streaming_update(state, chunk, preds, cfg, sil)
        pairs = {
            "chunk_preds": (ref_chunk_preds, chunk_preds),
            "spkcache": (ref_state.spkcache, state.spkcache),
            "spkcache_preds": (ref_state.spkcache_preds, state.spkcache_preds),
            "fifo": (ref_state.fifo, state.fifo),
            "fifo_preds": (ref_state.fifo_preds, state.fifo_preds),
            "mean_sil_emb": (ref_state.mean_sil_emb, state.mean_sil_emb[None]),
        }
        for name, (ref, got) in pairs.items():
            ref = None if ref is None else ref[0].numpy() if name != "mean_sil_emb" else ref.numpy()
            if ref is None or got is None:
                same = ref is None and got is None
            else:
                same = ref.shape == got.shape and np.allclose(ref, got, atol=1e-6)
            if not same:
                print(f"[ÉCHEC] bloc {step}: {name} différent")
            ok &= same
    if ok:
        print(f"[OK] {steps} blocs : cache, FIFO et prédictions identiques à NeMo")
    return ok


def _to_mlx_state(st) -> StreamingState:
    def arr(t):
        return None if t is None else t[0].detach().numpy().astype(np.float32).copy()

    fifo_preds = arr(st.fifo_preds)
    return StreamingState(
        spkcache=arr(st.spkcache),
        spkcache_preds=arr(st.spkcache_preds),
        fifo=arr(st.fifo),
        fifo_preds=fifo_preds if fifo_preds is not None else np.zeros((0, st.mean_sil_emb.shape[1]), np.float32),
        mean_sil_emb=arr(st.mean_sil_emb),
        n_sil_frames=int(st.n_sil_frames[0]),
        spkcache_compressed=bool(st.spkcache_compressed),
    )


class _GuidedDiarizer(StreamingDiarizer):
    """Repart de l'état NeMo avant chaque bloc : isole les écarts propres à chaque étape."""

    def __init__(self, model, states):
        super().__init__(model)
        self._states = list(states)

    def _step(self, end, right):
        self.state = _to_mlx_state(self._states.pop(0))
        return super()._step(end, right)


def check_streaming(ref_model, mlx_model, audio: np.ndarray) -> bool:
    """`StreamingDiarizer` (audio poussé par morceaux) contre `forward_streaming` de NeMo."""
    mods = mlx_model.config.modules
    chunk_s = mods.chunk_len * mlx_model.config.encoder.subsampling_factor * 0.01
    print(f"== Streaming ({len(audio) / 16000:.0f} s, blocs de {chunk_s:.1f} s)")
    ok = True

    # Référence NeMo, en mémorisant l'état avant chaque bloc et la sortie de chaque bloc.
    states, bounds = [], []
    step_fn = ref_model.forward_streaming_step

    def spy_step(*args, **kwargs):
        st = kwargs["streaming_state"]
        states.append(copy.deepcopy(st))
        before = kwargs["total_preds"].shape[1]
        out = step_fn(*args, **kwargs)
        bounds.append((before, out[1].shape[1]))
        return out

    with torch.no_grad():
        signal = torch.from_numpy(audio)[None]
        length = torch.tensor([signal.shape[1]])
        ref_feats, ref_len = ref_model.preprocessor(input_signal=signal, length=length)
        ref_feats = ref_feats[:, :, : ref_len.max()]
        ref_model.forward_streaming_step = spy_step
        try:
            with stable_topk():
                ref_preds, _, ref_activity = ref_model.forward_streaming(ref_feats, ref_len, return_logits=True)
        finally:
            del ref_model.forward_streaming_step
    ref_preds = ref_preds[0].numpy()
    ref_act = torch.softmax(ref_activity[0], dim=-1).numpy() if ref_activity is not None else None

    # 1) Guidé : chaque bloc part de l'état exact de NeMo -> tolérance stricte.
    guided = _GuidedDiarizer(mlx_model, states)
    g_out = [guided.feed(audio), guided.flush()]
    g_preds = np.concatenate([o.preds for o in g_out])
    ok &= report(f"guidé ({len(states)} blocs)", ref_preds, g_preds, atol=1e-4)
    if ref_act is not None:
        ok &= report("guidé, activité", ref_act, np.concatenate([o.activity for o in g_out]), atol=1e-4)

    # 2) Libre, audio poussé par morceaux irréguliers comme un flux micro.
    rng = np.random.default_rng(2)
    diarizer = StreamingDiarizer(mlx_model)
    pos, outs = 0, []
    while pos < len(audio):
        step = int(rng.integers(100, 24000))
        outs.append(diarizer.feed(audio[pos : pos + step]))
        pos += step
    outs.append(diarizer.flush())
    preds = np.concatenate([o.preds for o in outs])
    contiguous = all(o.start_frame == sum(len(p.preds) for p in outs[:i]) for i, o in enumerate(outs))
    print(f"[{'OK' if contiguous else 'ÉCHEC'}] {len(outs)} appels feed/flush, sorties contiguës")
    ok &= contiguous
    if preds.shape != ref_preds.shape:
        print(f"[ÉCHEC] libre : formes {ref_preds.shape} != {preds.shape}")
        return False
    per_chunk = [np.abs(ref_preds[a:b] - preds[a:b]).max() for a, b in bounds]
    first = next((i for i, d in enumerate(per_chunk) if d > 1e-4), None)
    diff = np.abs(ref_preds - preds)
    note = "aucune" if first is None else f"à partir du bloc {first}"
    print(
        f"[INFO] libre               écart max={diff.max():.3e} moyen={diff.mean():.3e} ; divergence > 1e-4 : {note}"
    )
    if first is not None:
        # Une divergence libre n'est acceptable que si le mode guidé est exact :
        # elle provient alors d'un ex-aequo de score départagé par l'arrondi.
        print("       (le mode guidé étant exact, elle vient d'un ex-aequo de sélection du cache "
              "départagé différemment par l'arrondi flottant)")
    ok &= report("libre (tolérance)", ref_preds, preds, atol=5e-2)

    # Les features incrémentales doivent égaler celles calculées d'un bloc.
    inc = IncrementalLogMel(mlx_model.preprocessor_window, mlx_model.preprocessor_fb, mlx_model.config.preprocessor)
    pos, parts = 0, []
    while pos < len(audio):
        step = int(rng.integers(1, 9000))
        parts.append(np.array(inc.push(audio[pos : pos + step])))
        pos += step
    parts.append(np.array(inc.flush()))
    whole, _ = log_mel(
        mx.array(audio), mlx_model.preprocessor_window, mlx_model.preprocessor_fb, mlx_model.config.preprocessor
    )
    ok &= report("features incrém.", np.array(whole), np.concatenate(parts), atol=1e-4)
    return ok


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("nemo")
    parser.add_argument("audio", nargs="?")
    parser.add_argument("--seconds", type=float, default=20.0, help="durée du test hors-ligne (audio synthétique)")
    parser.add_argument(
        "--streaming-seconds", type=float, default=95.0, help="durée du test streaming (audio synthétique)"
    )
    args = parser.parse_args()

    ref_model = SortformerEncLabelModel.restore_from(args.nemo, map_location="cpu")
    ref_model.eval()
    sr = ref_model.cfg.sample_rate
    if args.audio:
        long_audio = load_audio(args.audio, sr)
        short_audio = long_audio[: int(args.seconds * sr)]
    else:
        short_audio = synthetic_audio(args.seconds, sr)
        long_audio = synthetic_audio(args.streaming_seconds, sr)

    with tempfile.TemporaryDirectory() as tmp:
        convert(args.nemo, tmp)
        mlx_model = Model.from_pretrained(tmp)

    ok = check_offline(ref_model, mlx_model, short_audio)
    ok &= check_compression(ref_model, mlx_model)
    ok &= check_streaming_update(ref_model, mlx_model)
    ok &= check_streaming(ref_model, mlx_model, long_audio)
    print(f"Sortie : trames de {mlx_model.frame_duration * 1000:.0f} ms, {mlx_model.config.modules.num_spks} interlocuteurs")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
