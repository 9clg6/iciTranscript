# server_probe

This probe runs the app's protocol against a real `voxmlx-serve`, on its own port and never on 8000. Logs are written as JSONL to `$PROBE_DIR/logs` (default: `$TMPDIR/voxmlx_probe`).

1. Start a server in its own process group (no `--parent-pid`, no downloads):
   `HF_HUB_OFFLINE=1 perl -e 'setpgrp(0,0); exec @ARGV' uvx --offline --python 3.12 --from 'git+https://github.com/T0mSIlver/voxmlx.git@2ea0639570e447493d04349d96a41f71c031ae0d[server]' voxmlx-serve --model T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit --port 8017 &`
2. Wait for `curl -sf http://127.0.0.1:8017/health`.
3. Generate the audio (macOS `say` and `afconvert`, 16 kHz mono PCM16): `uv run --with websockets python tool/server_probe/probe.py gen`
4. Run one question at a time: `probe.py q1|q2|q3|q4|q5`, `q6 [--load]`, and `q7 --minutes 15 --server-pid <python pid>`.
5. Each run writes `<run>.jsonl` (every message, timestamped) and `<run>.summary.json`. The summary gives commit-to-`done` time, first text delta after speech onset, and WER.
6. Stop the server by killing its process group only: `kill -- -<pgid>`. Then check that `lsof -iTCP:8017` is empty.
