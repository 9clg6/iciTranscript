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
| Streaming (cache d'interlocuteurs, FIFO, compression) | ✅ |
| Features mel incrémentales (audio poussé par morceaux) | ✅ |
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
out = model(audio_16k_mono)   # np.ndarray float32, 16 kHz
out["preds"]     # (trames, 8) probabilité d'activité par interlocuteur
out["activity"]  # (trames, 3) silence / une voix / chevauchement
model.frame_duration  # 0.01 s
```

Comme NeMo, `model(...)` choisit le mode selon la config : Nemotron 3 est
entraîné en streaming, donc l'audio est traité par blocs de 264 trames
d'encodeur (≈ 21 s), chacun encodé avec le cache d'interlocuteurs devant lui.
La mémoire reste constante quelle que soit la durée, et la numérotation des
interlocuteurs reste cohérente d'un bloc à l'autre. `model.forward_offline`
force l'attention sur tout le signal (coût quadratique, extraits courts).

Pour un flux en direct (micro, audio système), `StreamingDiarizer` accepte
l'audio par morceaux de taille quelconque :

```python
from nemotron_diar_mlx.streaming import StreamingDiarizer

diar = StreamingDiarizer(model)
for block in audio_blocks:          # np.float32, 16 kHz
    out = diar.feed(block)          # trames finalisées depuis l'appel précédent
    handle(out.start_frame, out.preds, out.activity)
handle_last(diar.flush())
```

Les résultats sont produits bloc par bloc : une trame est disponible au plus
tard ≈ 21 s après avoir été prononcée (taille de bloc de Nemotron 3). Les
sorties concaténées sont identiques à un appel unique sur le signal complet.

## Validation

`scripts/check_parity.py` compare MLX et NeMo (PyTorch, CPU) étape par étape
sur un même `.nemo`. Sans les vrais poids, `scripts/make_random_nemo.py` crée
un checkpoint aléatoire ayant exactement l'architecture cible (99,2 M
paramètres) :

```bash
python scripts/make_random_nemo.py <NeMo>/examples/speaker_tasks/diarization/conf/neural_diarizer/sortformer_streaming_8spk.yaml random.nemo
python scripts/check_parity.py random.nemo [audio_16k.wav]
```

Le script vérifie :

- le chemin hors-ligne étape par étape (features mel, encodeur, logits,
  probabilités, activité) ;
- la compression du cache d'interlocuteurs (entrées aléatoires, dont la
  moitié avec trames dupliquées) et l'état streaming complet après chaque bloc
  (cache, FIFO, prédictions) : identiques bit à bit à NeMo ;
- le streaming de bout en bout contre `forward_streaming` de NeMo, en mode
  **guidé** (chaque bloc repart de l'état NeMo : tolérance 1e-4) et en mode
  **libre** (audio poussé par morceaux irréguliers, comme un micro) ;
- les features incrémentales contre le calcul en un bloc.

Résultats sur poids aléatoires (MLX CPU contre NeMo CPU, float32), pour les
deux variantes (streaming 10 ms et offline 80 ms) : écart maximal ≈ 1e-4 sur
les features mel (valeurs ≈ 16), ≈ 6e-6 en sortie d'encodeur, ≈ 7e-7 sur les
probabilités en hors-ligne comme en streaming guidé ; features incrémentales
identiques. Des erreurs volontaires (variante de RoPE, ordre de l'upsampling,
tri du cache, prédictions périmées dans le cache) sont toutes détectées. En
bfloat16, les probabilités restent à moins de 1e-2 du float32.

### Ex-aequo dans la sélection du cache

La compression garde les trames de meilleur score via `torch.topk`, qui ne
spécifie pas quel élément retenir entre valeurs égales. Des scores égaux
existent (trames identiques, ex. silence numérique) : le portage les départage
de façon déterministe (trame la plus ancienne d'abord) et le test impose la
même règle à NeMo. En mode libre, un ex-aequo exact chez NeMo peut toutefois
être départagé par l'arrondi flottant côté MLX (écart de 1e-7 sur les
entrées) : sur 130 s d'audio de test, cela a modifié un bonus de sélection au
5ᵉ bloc, avec un écart maximal de 2,7e-4 sur les probabilités de ce bloc et
≈ 1e-6 ailleurs. C'est inhérent à toute réimplémentation (NeMo lui-même n'est
pas garanti identique entre CPU et GPU sur ce point) ; le mode guidé confirme
que chaque étape est exacte.

Les mêmes scripts tournent sous Linux (`mlx[cpu]`), ce qui permet de valider le
portage sans Mac ; les performances réelles se mesurent sur Apple Silicon.
