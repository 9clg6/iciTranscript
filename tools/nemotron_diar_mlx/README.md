# nemotron-diar-mlx

Portage MLX (Apple Silicon) de [NVIDIA Nemotron 3 Diarization](https://huggingface.co/nvidia/Nemotron-3-Diarization) :
identification de jusqu'à 8 interlocuteurs (« qui parle quand »), destinée à
remplacer pyannote + TitaNet dans la passe post-session d'IciTranscript.

## État

| Étape | État |
|---|---|
| Features log-mel 128 bandes (identiques à `FilterbankFeatures`) | ✅ |
| Encodeur Transformer (empilement ×8, 31 blocs RoPE pré-norm) | ✅ |
| Têtes Sortformer (projection, upsampling ×8 → 10 ms, interlocuteurs, activité) | ✅ |
| Convertisseur `.nemo` → MLX (float32 / float16 / bfloat16) | ✅ |
| Inférence hors-ligne (attention complète) | ✅ |
| Streaming (cache d'interlocuteurs, enregistrements longs) | à faire |
| Validation sur les vrais poids | à faire (accès Hugging Face requis) |

L'architecture vient de `sortformer_streaming_8spk.yaml` de NeMo, documenté
comme configuration d'entraînement de Nemotron-3-Diarization. La variante
« offline » de première étape (`sortformer_offline_8spk.yaml`, sortie à 80 ms)
est aussi supportée. Les anciens Sortformer v2.x (encodeur FastConformer) sont
refusés explicitement par le convertisseur.

## Utilisation

```bash
uv run --python 3.12 --with ".[convert]" python -m nemotron_diar_mlx.convert \
    Nemotron-3-Diarization.nemo nemotron3-diar-mlx --dtype bfloat16
```

```python
import mlx.core as mx
from nemotron_diar_mlx import Model

model = Model.from_pretrained("nemotron3-diar-mlx", dtype=mx.bfloat16)
out = model(mx.array(audio_16k_mono))   # float32, 16 kHz
out["preds"]     # (trames, 8) probabilité d'activité par interlocuteur
out["activity"]  # (trames, 3) silence / une voix / chevauchement
model.frame_duration  # 0.01 s
```

L'inférence hors-ligne applique une attention complète sur tout
l'enregistrement : coût quadratique en durée. Elle convient aux extraits de
quelques minutes ; les réunions longues passeront par le mode streaming
(prochaine étape).

## Validation

`scripts/check_parity.py` compare MLX et NeMo (PyTorch, CPU) étape par étape
sur un même `.nemo`. Sans les vrais poids, `scripts/make_random_nemo.py` crée
un checkpoint aléatoire ayant exactement l'architecture cible (99,2 M
paramètres) :

```bash
python scripts/make_random_nemo.py <NeMo>/examples/speaker_tasks/diarization/conf/neural_diarizer/sortformer_streaming_8spk.yaml random.nemo
python scripts/check_parity.py random.nemo [audio_16k.wav]
```

Résultats sur poids aléatoires (MLX CPU contre NeMo CPU, float32) : écart
maximal ≈ 1e-4 sur les features mel, ≈ 6e-6 en sortie d'encodeur et ≈ 7e-7 sur
les probabilités. Le test détecte bien des erreurs volontaires (variante de
RoPE, ordre de l'upsampling). En bfloat16, les probabilités restent à moins de
1e-2 du float32.

Les mêmes scripts tournent sous Linux (`mlx[cpu]`), ce qui permet de valider le
portage sans Mac ; les performances réelles se mesurent sur Apple Silicon.
