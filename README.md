# Oats

**Real-time voice transcription for macOS — on-device by default.**

Oats (formerly **iciTranscript**) captures your microphone and your Mac's system audio, transcribes both in real time with on-device MLX models, and can summarise a meeting or coach your spoken English with a local model. Online AI providers are optional and off by default; audio never leaves your Mac.

---

## Features

- **Real-time transcription** — words appear as you speak, powered by [voxmlx](https://github.com/T0mSIlver/voxmlx) and Apple Silicon MLX
- **Two audio sources, kept separate** — your microphone and the system audio (calls, videos) are captured as two streams, so the note knows who said what ("Vous" vs. the other side)
- **Notes by day** — every recording is saved and listed on the home page, grouped by day, with search
- **Speaker diarization** — after a session, remote participants (system audio) are separated and labelled, up to 8 speakers, with NVIDIA Nemotron 3 Diarization on MLX ([nemotron-diar-mlx](https://github.com/9clg6/nemotron-diar-mlx)); the model (~400 MB) is downloaded on first use
- **Summaries and English coach (optional)** — a local [Mistral](https://mistral.ai) model via Ollama; install it once from **Réglages › Modèle local** (Ollama ~106 MB + model ~4 GB). Long meetings are summarised in full, part by part. Without a model, transcription works and the note shows how to set one up
- **Online providers (optional, off by default)** — Claude, OpenAI or Gemini with your own API key (stored in the macOS Keychain), once you turn on online sending in **Réglages**
- **Documents** — add .txt, .md or .pdf files as sources for answers during your meetings; their text is indexed on your Mac
- **Export** — copy a transcript or export it as Markdown to `~/Downloads/`
- **Private by default** — your audio never leaves your Mac; no accounts, no subscriptions, no telemetry

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

The transcription server (`voxmlx-serve`) runs as a child process launched by the app via `uvx`. It listens on `ws://127.0.0.1:8000` (8100 for a dev build on its own data directory; live diarization uses 8001/8101) and streams transcript segments back in real time. The app records the servers it starts in `servers.json` in its data directory and only ever stops those; a port held by another program is reported, never freed.

---

## Privacy

- All audio processing happens **on your device**: audio never leaves your Mac
- Online AI providers (Claude, OpenAI, Gemini) are optional and off by default. Nothing is sent to them until you add a key and turn on online sending in Réglages
- When online sending is on, the transcript text of a note (for a summary or the English coach) and excerpts of your documents are sent to the provider you chose; turn it off to keep everything on your Mac
- No analytics, no crash reporting, no telemetry
- Notes are stored locally in `~/Library/Application Support/IciTranscript/`

---

## License

MIT
