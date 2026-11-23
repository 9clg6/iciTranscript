"""Probe the real Mistral realtime transcription API with synthetic audio.

The API key is read from the macOS keychain inside this process only; it
is never printed, logged or passed on a command line. Every server message
is recorded verbatim (JSON line + arrival time) for spec fixtures.

uv run --with websockets --with httpx python tool/server_probe/mistral_probe.py <test> --out DIR
tests: stream, flush, fast, badkey, model2602, batch
"""

import argparse
import asyncio
import base64
import io
import json
import os
import subprocess
import sys
import time
import wave
from pathlib import Path

import httpx
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

sys.path.insert(0, str(Path(__file__).parent))
from probe import AUDIO, wer  # noqa: E402

RATE, CHUNK = 16000, 3200
WS = "wss://api.mistral.ai/v1/audio/transcriptions/realtime?model={model}"
RT_MODEL = "voxtral-mini-transcribe-realtime-3-0"
T0 = time.monotonic()


def key():
    return subprocess.run(
        ["security", "find-generic-password", "-s", "fr.yellowstone-apps.ici-transcript", "-a", "mistral", "-w"],
        capture_output=True, text=True, check=True).stdout.strip()


def now():
    return round(time.monotonic() - T0, 3)


class Log:
    def __init__(self, path):
        self.f = open(path, "w")

    def w(self, **kv):
        self.f.write(json.dumps({"t": now(), **kv}, ensure_ascii=False) + "\n")
        self.f.flush()


def bench(src="mic"):
    with wave.open(str(AUDIO / "paused" / f"{src}.wav")) as w:
        pcm = w.readframes(w.getnframes())
    sched = json.loads((AUDIO / "paused" / "schedule.json").read_text())[src]
    return pcm, sched


def ref_text(sched, a, b):
    return " ".join(s["text"] for s in sched if s["start"] >= a and s["end"] <= b)


async def session(log, api_key, model=RT_MODEL, delay_ms=480):
    try:
        ws = await connect(WS.format(model=model), additional_headers={"Authorization": f"Bearer {api_key}"},
                           max_size=None, open_timeout=20, ping_interval=None)
    except InvalidStatus as e:
        r = e.response
        log.w(dir="http_reject", status=r.status_code, reason=r.reason_phrase,
              headers={h: v for h, v in r.headers.raw_items() if h.lower() != "set-cookie"},
              body=r.body.decode(errors="replace")[:2000])
        raise
    log.w(dir="open", model=model)

    async def reader():
        try:
            async for raw in ws:
                log.w(dir="in", raw=json.loads(raw))
        except Exception as e:  # noqa: BLE001
            log.w(dir="reader_error", err=repr(e))
        log.w(dir="closed", code=ws.close_code, reason=ws.close_reason)

    task = asyncio.create_task(reader())
    await send(ws, log, {"type": "session.update", "session": {
        "audio_format": {"encoding": "pcm_s16le", "sample_rate": RATE}, "target_streaming_delay_ms": delay_ms}})
    return ws, task


async def send(ws, log, msg):
    await ws.send(json.dumps(msg))
    if msg["type"] == "input_audio.append":
        log.w(dir="out", type=msg["type"], bytes=len(base64.b64decode(msg["audio"])))
    else:
        log.w(dir="out", **msg)


async def stream(ws, log, pcm, speed=1.0):
    start = time.monotonic()
    for i in range(0, len(pcm), CHUNK):
        await asyncio.sleep(max(0.0, start + (i / CHUNK) * 0.1 / speed - time.monotonic()))
        await send(ws, log, {"type": "input_audio.append",
                             "audio": base64.b64encode(pcm[i:i + CHUNK]).decode()})


async def end_and_wait(ws, task, log, wait=30):
    await send(ws, log, {"type": "input_audio.end"})
    try:
        await asyncio.wait_for(asyncio.shield(task), wait)
    except asyncio.TimeoutError:
        log.w(dir="note", msg=f"socket still open {wait}s after end; closing")
        await ws.close()
        await task


async def t_stream(a, k):  # 1 + 3: 60 s with pauses, real time, then end
    log = Log(a.out / "stream.jsonl")
    pcm, sched = bench()
    ws, task = await session(log, k)
    await stream(ws, log, pcm[:60 * RATE * 2])
    await end_and_wait(ws, task, log)
    log.w(dir="ref", text=ref_text(sched, 0, 60))


async def t_flush(a, k):  # 2: a flush after each sentence; empty flushes
    log = Log(a.out / "flush.jsonl")
    pcm, sched = bench("sys")
    ws, task = await session(log, k)
    sil = bytes(int(1.2 * RATE) * 2)
    for s in [x for x in sched if x["end"] <= 60][:5]:
        clip = pcm[int(s["start"] * RATE) * 2:int(s["end"] * RATE) * 2]
        log.w(dir="sentence", i=s["i"], text=s["text"])
        await stream(ws, log, clip + sil)
        await send(ws, log, {"type": "input_audio.flush"})
        await asyncio.sleep(4)
    await stream(ws, log, bytes(2 * RATE * 2))  # 2 s silence, no speech
    await send(ws, log, {"type": "input_audio.flush"})
    await asyncio.sleep(4)
    await send(ws, log, {"type": "input_audio.flush"})  # flush with no audio at all
    await asyncio.sleep(4)
    await end_and_wait(ws, task, log)


async def t_fast(a, k):  # 4: 2x pacing, then 20 s with nothing sent
    log = Log(a.out / "fast.jsonl")
    pcm, sched = bench()
    ws, task = await session(log, k)
    await stream(ws, log, pcm[60 * RATE * 2:90 * RATE * 2], speed=2.0)
    log.w(dir="note", msg="idle 20 s, nothing sent")
    await asyncio.sleep(20)
    await stream(ws, log, pcm[90 * RATE * 2:95 * RATE * 2], speed=1.0)
    await end_and_wait(ws, task, log)
    log.w(dir="ref", text=ref_text(sched, 60, 95))


async def t_badkey(a, k):  # 5: fake key
    log = Log(a.out / "badkey.jsonl")
    try:
        async with connect(WS.format(model=RT_MODEL), additional_headers={"Authorization": "Bearer not-a-real-key"},
                           open_timeout=20) as ws:
            log.w(dir="open")
            await ws.send(json.dumps({"type": "session.update", "session": {}}))
            async for raw in ws:
                log.w(dir="in", raw=json.loads(raw))
            log.w(dir="closed", code=ws.close_code, reason=ws.close_reason)
    except InvalidStatus as e:
        r = e.response
        log.w(dir="http_reject", status=r.status_code, reason=r.reason_phrase,
              headers={h: v for h, v in r.headers.raw_items() if h.lower() not in ("set-cookie",)},
              body=r.body.decode(errors="replace")[:2000])
    except Exception as e:  # noqa: BLE001
        log.w(dir="error", err=repr(e))


async def t_model2602(a, k):  # 5b: other model, 20 s
    log = Log(a.out / "model2602.jsonl")
    pcm, sched = bench()
    ws, task = await session(log, k, model="voxtral-mini-transcribe-realtime-2602")
    await stream(ws, log, pcm[:20 * RATE * 2])
    await end_and_wait(ws, task, log)
    log.w(dir="ref", text=ref_text(sched, 0, 20))


def t_batch(a, k):  # 6: 30 s WAV, segment timestamps
    log = Log(a.out / "batch.jsonl")
    pcm, sched = bench()
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(pcm[:30 * RATE * 2])
    t = time.monotonic()
    r = httpx.post("https://api.mistral.ai/v1/audio/transcriptions",
                   headers={"Authorization": f"Bearer {k}"},
                   data={"model": "voxtral-mini-transcribe-3-0", "timestamp_granularities": "segment"},
                   files={"file": ("bench30.wav", buf.getvalue(), "audio/wav")}, timeout=120)
    log.w(dir="http", status=r.status_code, latency_s=round(time.monotonic() - t, 2),
          body=r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text[:2000])
    log.w(dir="ref", text=ref_text(sched, 0, 30))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("test", choices=["all", "stream", "flush", "fast", "badkey", "model2602", "batch"])
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    k = None if a.test == "badkey" else key()  # one keychain call per run
    if a.test == "all":
        print("key read", flush=True)  # never the key itself
        for t in ("stream", "flush", "fast", "model2602"):
            print("test", t, flush=True)
            asyncio.run(globals()[f"t_{t}"](a, k))
        print("test batch", flush=True)
        return t_batch(a, k)
    if a.test == "batch":
        return t_batch(a, k)
    asyncio.run(globals()[f"t_{a.test}"](a, k))


if __name__ == "__main__":
    main()
