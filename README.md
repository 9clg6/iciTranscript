# Oats

**Real-time voice transcription for macOS — 100% local, zero cloud.**

Oats (formerly **iciTranscript**) captures your microphone and your Mac's system audio, transcribes both in real time with on-device MLX models, and can summarise a meeting or coach your spoken English with a local model — without sending a single byte to the cloud.

---

## Features

- **Real-time transcription** — words appear as you speak, powered by [voxmlx](https://github.com/T0mSIlver/voxmlx) and Apple Silicon MLX
- **Two audio sources, kept separate** — your microphone and the system audio (calls, videos) are captured as two streams, so the note knows who said what ("Vous" vs. the other side)
- **Notes by day** — every recording is saved and listed on the home page, grouped by day, with search
- **Speaker diarization** — after a session, remote participants (system audio) are separated and labelled, up to 8 speakers, with NVIDIA Nemotron 3 Diarization on MLX ([nemotron-diar-mlx](https://github.com/9clg6/nemotron-diar-mlx)); the model (~400 MB) is downloaded on first use
- **Summaries and English coach (optional)** — a local [Mistral](https://mistral.ai) model via Ollama; install it once from **Réglages › Modèle local** (Ollama ~106 MB + model ~4 GB). Without it, transcription works and the note shows how to set it up
- **Export** — copy a transcript or export it as Markdown to `~/Downloads/`
- **100% local & private** — your audio never leaves your Mac; no accounts, no subscriptions, no telemetry

---

## Minimum Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| macOS | 13 Ventura | 14 Sonoma or later |
| Chip | Apple M1 | Apple M2 / M3 |
| RAM | 8 GB | 16 GB |
| Disk | 5 GB free | 10 GB free |

> **Why Apple Silicon?** The transcription engine uses MLX, Apple's machine learning framework for M-series chips. Intel Macs are not supported.

---

## Installation

1. **Download** `Oats-vX.Y.Z.dmg` from [GitHub Releases](../../releases)
2. **Drag** Oats into your Applications folder
3. **Right-click › Open** on first launch (Gatekeeper warning — the app is ad-hoc signed)
4. Grant **Microphone** and **Screen Recording** permissions when prompted

`uv` (used to run the transcription server) is installed by the app on first launch if missing. The local model for summaries is optional and installed only when you ask for it in Réglages.

Data stays where iciTranscript kept it (`~/Library/Application Support/IciTranscript/`), so existing notes and models carry over.

---

## Development

### Prerequisites

- Flutter SDK 3.x
- Xcode 15+
- `uv` — [astral.sh/uv](https://astral.sh/uv)

### Getting started

```bash
cd apps/app_macos && flutter pub get
flutter run -d macos     # debug run
flutter test             # tests
flutter analyze          # lints
cd ../.. && make build   # release build (Oats.app)
make dmg                 # Oats-vX.Y.Z.dmg
```

### Project structure

```
apps/app_macos/        — Flutter macOS application
packages/
  core_domain/         — Entities, use cases, repository interfaces
  core_data/           — Repository implementations, Drift SQLite database
  core_foundation/     — Logger, config, shared utilities
  core_presentation/   — Oats design tokens, theme and shared widgets
```

### Architecture

- **Presentation** — Flutter widgets + Riverpod ViewModels (Freezed state)
- **Application** — LiveTranscriptionService orchestrating audio capture, WebSocket and database
- **Domain** — Pure Dart use cases and entities
- **Data** — Drift SQLite + platform channels (Swift) for audio and process management

The transcription server (`voxmlx-serve`) runs as a child process launched by the app via `uvx`. It listens on `ws://localhost:8000` and streams transcript segments back in real time.

---

## Privacy

- All audio processing happens **on your device**
- No data is sent to any external server
- No analytics, no crash reporting, no telemetry
- Notes are stored locally in `~/Library/Application Support/IciTranscript/`

---

## License

MIT
