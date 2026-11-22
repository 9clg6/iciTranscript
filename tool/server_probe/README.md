# server_probe

Measurement tools that run the app's client code against a real `voxmlx-serve`. They are not part of the test suite. Logs are timestamped JSONL under `$PROBE_DIR` (default `$TMPDIR/voxmlx_probe`).

## Safety rules

- Run your own server on port **8017**, in its own process group. Stop it with `kill -- -<pgid>` only. Never use `pkill` or `killall`, and never kill a process you did not start.
- Never use ports 8000/8001 (the installed app), 8100/8101 (dev builds) or 11434 (Ollama). The proxy uses 8018 (mic) and 8019 (system).
- Work offline (`HF_HUB_OFFLINE=1`, `uvx --offline`), and never pass `--parent-pid`.
- Use synthetic `say` audio only.
- Never launch the Flutter app, and never touch `~/Library/Application Support`. Under `flutter test`, the app's data folder is a fresh temporary folder.
- When done, check `lsof -iTCP:8017 -iTCP:8018 -iTCP:8019` is empty.

## Server

```sh
HF_HUB_OFFLINE=1 perl -e 'setpgrp(0,0); exec @ARGV' uvx --offline --python 3.12 \
  --from 'git+https://github.com/T0mSIlver/voxmlx.git@2ea0639570e447493d04349d96a41f71c031ae0d[server]' \
  voxmlx-serve --model T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit --port 8017 >> $PROBE_DIR/server.log 2>&1 &
echo $! > $PROBE_DIR/server.pid   # = process group id
until curl -sf http://127.0.0.1:8017/health; do sleep 0.3; done
```

## Audio (`probe.py`, run with `uv run --with websockets python tool/server_probe/probe.py …`)

- `gen`: clips for the protocol questions.
- `timeline [--seconds 300] [--name live]`: two 16 kHz mono PCM16 timelines (`mic.wav`, `sys.wav`) of unique sentences, plus `schedule.json`. Use `--seconds 3600 --name live60` for the long run.

## 1. Protocol questions (raw WebSocket)

- Commands: `probe.py q1` … `q5`, `q6 [--load]`, `q7 --minutes 15 --server-pid <python pid>`.
- Each run writes `logs/<run>.jsonl` and `<run>.summary.json`: commit→`done` time, first text after speech onset, WER.

## 2. Real Dart client with faults (`packages/core_data/tool/live_probe.dart`)

Drives `TranscriptionRemoteDataSourceImpl` and `WebSocketClient` through the fault proxy (`probe_proxy.dart`). Run from `packages/core_data`:

```sh
[LIVE_SECONDS=300] [STOP_SKIP_AFTER=3] dart run tool/live_probe.dart <scenario> $PROBE_DIR/audio/live <run.jsonl> $PROBE_DIR
```

Scenarios:
- `A`: no fault.
- `B`: four 3 s cuts on the mic.
- `C`: refusals of 20 s, then 60 s.
- `D`: a 150 s refusal.
- `E`: stalls of 30 s, then 90 s.
- `F`: the server group in `server.pid` is killed, then restarted after 15 s.
- `G`/`Gskip` (`LIVE_SECONDS=125`): stop during a catch-up, with or without skip.
- `L` (`LIVE_SECONDS=3600`, audio `live60`): long run.

The stop mirrors the app's: final commit, then a drain of at most 120 s. Each run also writes `<run>_mic.wav` and `<run>_system.wav` in the app's format.

Scoring: `probe.py score <run.jsonl>... [--audio live60 --window 300]`. It reports WER, missing, duplicated, in order, gaps, missing outside gaps, server closes → `onClosed`, buffer peak, delay, and footprint.

## 3. App services (`apps/app_macos/tool/*.dart`, run with `flutter test <file>`)

- `backfill_probe.dart`:
  - Env: `RUN_DIR=<dir with run.jsonl and WAVs>`, `RUN_NAME=<run>`, `OUT=<json>`, `URL=ws://127.0.0.1:8017/v1/realtime`.
  - Runs the real `GapBackfillService` and `WebSocketPcmTranscriber` on the run's gaps.
  - `MODE=retry`: drives `GapBackfillRetry` with the server absent, then starts the server itself (`SERVER_CMD`, `PROBE_DIR`) and snapshots `.backfill_pending.json`.
- `service_probe.dart`:
  - Env: `MODE=D|long20|b2b|yield|kill|relaunch|lang|langcheck`, `AUDIO=$PROBE_DIR/audio`, `STATE=<dir>`, `OUT=<jsonl>`.
  - Drives the real `LiveTranscriptionService`, with the repo's fakes for capture and the process manager only. Sessions and segments persist to `STATE/state.json`.
  - `D`: 150 s refusal, then the stop drain and backfill. `long20`: 20 min of `live60` with a 3 s cut and a 45 s refusal.
  - `b2b`: meeting B starts 2 s after stopping A during a catch-up. `yield`: B starts while A's backfill is in flight.
  - `kill` kills its own process during an outage; `relaunch` then replays the launch path (repair, WAV repair, enqueue, `retryPending`).
  - `lang`: replays the two long-run wrong-language utterances 5 times each.
  - `langcheck` (`FILES=a.jsonl,b.jsonl`): counts language-check flags on the reference sentences and on real `done` texts.
  - Score a run: `probe.py svcscore <run.jsonl> [--audio live60 --window 300]`. It reports WER, missing sentences, duplicated 4-grams, markers and partials left, and delay.
