"""Probe a real voxmlx-serve over its WebSocket protocol.

Generates `say` audio, streams it paced like the app (100 ms PCM16 chunks,
1.2 s silence tail, then a final commit) and logs every message with
timestamps to JSONL. One subcommand per question; see README.md.
"""

import argparse
import asyncio
import base64
import json
import math
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
import time
import unicodedata
import wave
from pathlib import Path

from websockets.asyncio.client import connect

RATE = 16000
CHUNK = 3200  # 100 ms of PCM16 mono 16 kHz
TAIL_MS = 1200  # the client keeps 1.2 s of silence before its final commit
T0 = time.monotonic()

FR, EN = ("Thomas", "Jacques"), ("Samantha", "Daniel")

TEXTS = {
    "short_fr": (FR[0], "Bonjour à tous, nous pouvons commencer."),
    "mid_fr": (FR[0], "Le comité a validé le nouveau plan de jardin pour la place du marché. "
               "Les travaux commencent au printemps et dureront plusieurs semaines. "
               "Les habitants pourront donner leur avis lors de la prochaine réunion publique."),
    "long_en": (EN[0], "The library committee met on a quiet afternoon to talk about the reading room. "
                "Everyone agreed that the old wooden tables should stay, but the lamps need to be replaced "
                "because the light is too weak in the evening. A volunteer offered to paint the walls a soft "
                "green colour, and another proposed a small corner for children with cushions and picture books. "
                "The group will meet again next month to choose the furniture. "
                "Before that, two members will visit the shop in the next town to compare chairs, "
                "and the treasurer will check how much money is left after the roof repair."),
    "other_en": (EN[1], "The weather station on the hill records wind and rain every morning, "
                 "and the results are posted on the board near the bakery."),
    "dict_en": (EN[0], "Remind me to send the garden photos to the whole team tomorrow morning."),
    "dict_fr": (FR[1], "Note pour plus tard, acheter du papier et des enveloppes bleues."),
    "part1_en": (EN[0], "Our walking club starts every Saturday at the old stone bridge near the river. "
                 "We follow the path through the forest, past the mill and the orchard, and we usually stop "
                 "for a short rest at the top of the hill where the view over the valley is wide and calm. "
                 "Newcomers are always welcome, and nobody needs special equipment, only good shoes. "
                 "In winter the route is shorter because the forest path gets muddy, so we stay on the road "
                 "that climbs gently past the farms and the small chapel with the blue door."),
    "part2_en": (EN[0], "After the rest we walk down along the vineyard towards the village square, where "
                 "the baker keeps a table for the group and serves warm bread with honey. The walk ends there "
                 "around noon, and people who want to continue can join the longer afternoon loop that goes "
                 "around the lake and back to the bridge before the evening. "
                 "Once a month the club also cleans the path, picks up litter and repairs the wooden signs, "
                 "and these mornings finish with a shared lunch in the garden of the oldest member, "
                 "who always tells stories about the valley when she was young."),
}

# Long-run corpus: alternate FR/EN paragraphs, each well under 30 s.
PARAS = [
    "La bibliothèque du quartier ouvre une nouvelle salle de lecture au rez-de-chaussée. Les bénévoles ont repeint les murs et installé des étagères en bois clair.",
    "The bakery on the corner now opens earlier in the morning. The owner says that people on their way to work wanted fresh bread before the first train.",
    "Le marché du samedi accueille trois nouveaux producteurs de fruits et de légumes. Ils viennent des villages voisins et vendent surtout des pommes et des poireaux.",
    "The town council discussed the plan for a new cycling path along the river. Most residents support the idea, but some worry about the old trees near the bridge.",
    "Les enfants de l'école ont préparé un petit spectacle pour la fin de l'année. Ils ont fabriqué les costumes avec des tissus donnés par les parents.",
    "A group of neighbours started a shared garden behind the community hall. They grow beans, tomatoes and herbs, and anyone can help on Sunday afternoons.",
    "La piscine municipale fermera deux semaines pour remplacer le carrelage du grand bassin. Les cours de natation reprendront ensuite avec les mêmes horaires.",
    "The museum invited a local painter to show her landscapes in the east wing. The paintings show the hills and the lake in every season of the year.",
    "Le club de randonnée organise une sortie vers le lac au début du mois prochain. Il faut prévoir de bonnes chaussures, un pique-nique et une veste chaude.",
    "The music school is looking for volunteers to help with the summer concert. Tasks include setting up chairs, guiding visitors and selling lemonade at the door.",
    "Les habitants de la rue des tilleuls ont demandé un nouveau banc près de la fontaine. La mairie a accepté et le banc sera installé avant l'automne.",
    "The farmers market will move to the main square while the street is repaired. Stalls will stay open from early morning until lunch time as usual.",
]

PROBE = Path(os.environ.get("PROBE_DIR", Path(tempfile.gettempdir()) / "voxmlx_probe"))
AUDIO, LOGS = PROBE / "audio", PROBE / "logs"


def now():
    return round(time.monotonic() - T0, 3)


# ---------- audio ----------

def gen_one(name, voice, text):
    aiff, wav = AUDIO / f"{name}.aiff", AUDIO / f"{name}.wav"
    subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
    aiff.unlink()
    return {"voice": voice, "text": text, "sec": round(len(load(name)) / 2 / RATE, 2)}


def load(name):
    with wave.open(str(AUDIO / f"{name}.wav")) as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (RATE, 1, 2), name
        return w.readframes(w.getnframes())


def onset(pcm, thr=300):
    """Seconds until the first 100 ms chunk at the client's voice-start RMS."""
    for i in range(0, len(pcm) - CHUNK + 1, CHUNK):
        x = struct.unpack(f"<{CHUNK // 2}h", pcm[i:i + CHUNK])
        if math.sqrt(sum(v * v for v in x) / len(x)) >= thr:
            return i / CHUNK * 0.1
    return 0.0


def silence(ms):
    return bytes(ms * 32)


def noise(ms, dbfs=-50.0):
    # ponytail: stdlib Gaussian noise; RMS 32768*10^(dbfs/20) ~ 104 at -50 dBFS
    rms = 32768 * 10 ** (dbfs / 20)
    rnd = random.Random(7)
    n = ms * RATE // 1000
    return struct.pack(f"<{n}h", *(max(-32768, min(32767, int(rnd.gauss(0, rms)))) for _ in range(n)))


def cmd_gen(_):
    AUDIO.mkdir(parents=True, exist_ok=True)
    meta = {k: gen_one(k, v, t) for k, (v, t) in TEXTS.items()}
    for i, t in enumerate(PARAS):  # stream A: FR Thomas / EN Samantha; stream B: other voices
        fr = i % 2 == 0
        meta[f"pa{i}"] = gen_one(f"pa{i}", FR[0] if fr else EN[0], t)
        meta[f"pb{i}"] = gen_one(f"pb{i}", FR[1] if fr else EN[1], t)
    (AUDIO / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    for k, m in meta.items():
        print(k, m["voice"], m["sec"], "s")


def meta():
    return json.loads((AUDIO / "meta.json").read_text())


# ---------- WER ----------

def words(s):
    s = unicodedata.normalize("NFKC", s).lower()
    return re.sub(r"[^\w]+", " ", s).split()


def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return round(d[len(h)] / max(1, len(r)), 3)


# ---------- socket ----------

class Sock:
    def __init__(self, name, log, url):
        self.name, self.log, self.url = name, log, url
        self.utts = []  # one per final commit, in order
        self.cur = None  # utterance being streamed
        self.dones = 0
        self.unsolicited = []  # done received with no final commit outstanding
        self.deltas = ""

    def w(self, **kv):
        self.log.write(json.dumps({"t": now(), "sock": self.name, **kv}, ensure_ascii=False) + "\n")
        self.log.flush()

    async def open(self):
        self.ws = await connect(self.url, ping_interval=None, max_size=None, open_timeout=30)
        self.w(ev="open")
        self.reader = asyncio.create_task(self._read())

    async def _read(self):
        try:
            async for raw in self.ws:
                m = json.loads(raw)
                typ = m.get("type")
                outstanding = sum(1 for u in self.utts if u["t_commit"] and u["t_done"] is None)
                self.w(ev="in", type=typ, **{k: v for k, v in m.items() if k != "type"},
                       outstanding=outstanding)
                if typ == "response.audio_transcript.delta":
                    self.deltas += m["delta"]
                    u = self._oldest() or self.cur  # server is FIFO per socket
                    if u and u["t_first_delta"] is None and m["delta"].strip():
                        u["t_first_delta"] = now()
                elif typ == "response.audio_transcript.done":
                    self.dones += 1
                    u = self._oldest()
                    if u is None:
                        self.unsolicited.append({"t": now(), "text": m.get("text", ""),
                                                 "during": self.cur["label"] if self.cur else None})
                    else:
                        u["t_done"], u["text"], u["deltas"] = now(), m.get("text", ""), self.deltas
                    self.deltas = ""
        except Exception as e:  # noqa: BLE001
            self.w(ev="reader_error", err=repr(e))
        self.w(ev="closed", code=self.ws.close_code, reason=self.ws.close_reason)

    def _oldest(self):
        return next((u for u in self.utts if u["t_commit"] and u["t_done"] is None), None)

    def begin(self, label, ref=""):
        self.cur = {"sock": self.name, "label": label, "ref": ref, "t_first_append": None,
                    "t_commit": None, "t_first_delta": None, "t_done": None, "text": None}
        self.utts.append(self.cur)
        return self.cur

    async def stream(self, pcm, realtime=True):
        start = time.monotonic()
        for i in range(0, len(pcm), CHUNK):
            if realtime:
                await asyncio.sleep(max(0.0, start + i / CHUNK * 0.1 - time.monotonic()))
            await self.ws.send(json.dumps({"type": "input_audio_buffer.append",
                                           "audio": base64.b64encode(pcm[i:i + CHUNK]).decode()}))
            if self.cur and self.cur["t_first_append"] is None:
                self.cur["t_first_append"] = now()
        self.w(ev="out", type="append_done", ms=len(pcm) // 32)

    async def commit(self, final=True):
        msg = {"type": "input_audio_buffer.commit", **({"final": True} if final else {})}
        await self.ws.send(json.dumps(msg))
        self.w(ev="out", type="commit", final=final)
        if final:
            if self.cur is None or self.cur["t_commit"] is not None:
                self.begin("empty_commit")
            self.cur["t_commit"] = now()
            self.cur = None

    async def utter(self, label, pcm, ref="", realtime=True, tail=True):
        self.begin(label, ref)["onset_s"] = onset(pcm)
        await self.stream(pcm + (silence(TAIL_MS) if tail else b""), realtime)
        await self.commit()

    async def wait_all(self, timeout=120):
        end = time.monotonic() + timeout
        while self._oldest() and time.monotonic() < end:
            await asyncio.sleep(0.05)
        return self._oldest() is None

    async def abort(self):
        self.w(ev="abort")
        self.ws.transport.abort()
        self.reader.cancel()

    async def close(self):
        await self.ws.close()
        await asyncio.sleep(0.2)


def report(sock):
    rows = []
    for u in sock.utts:
        r = dict(u)
        r["commit_to_done"] = round(u["t_done"] - u["t_commit"], 3) if u["t_done"] else None
        r["first_delta_after_audio"] = (round(u["t_first_delta"] - u["t_first_append"] - u.get("onset_s", 0), 3)
                                        if u["t_first_delta"] and u["t_first_append"] else None)
        r["wer"] = wer(u["ref"], u["text"] or "") if u["ref"] else None
        r["deltas_match_done"] = (words(u.get("deltas") or "") == words(u["text"] or "")) if u["t_done"] else None
        rows.append(r)
    return {"sock": sock.name, "utts": rows, "unsolicited_done": sock.unsolicited, "dones": sock.dones}


class Run:
    def __init__(self, name, url):
        LOGS.mkdir(parents=True, exist_ok=True)
        self.name, self.url = name, url
        self.log = open(LOGS / f"{name}.jsonl", "a")
        self.socks = []
        self.log.write(json.dumps({"t": now(), "run": name, "wall": time.strftime("%H:%M:%S")}) + "\n")

    async def sock(self, name):
        s = Sock(name, self.log, self.url)
        await s.open()
        self.socks.append(s)
        return s

    def finish(self, extra=None):
        out = {"run": self.name, "socks": [report(s) for s in self.socks], **(extra or {})}
        (LOGS / f"{self.name}.summary.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
        for s in out["socks"]:
            for u in s["utts"]:
                print(f'{s["sock"]:>6} {u["label"]:<14} c2d={u["commit_to_done"]} fd={u["first_delta_after_audio"]} '
                      f'wer={u["wer"]} text={(u["text"] or "")[:90]!r}')
            if s["unsolicited_done"]:
                print(f'{s["sock"]:>6} UNSOLICITED done: {s["unsolicited_done"]}')
        return out


def clip(name, ms):
    return load(name)[: ms * 32]


# ---------- scenarios ----------

async def q1(a):
    m, r = meta(), Run("q1_commits", a.url)
    s = await r.sock("s")
    await s.commit()  # final commit on a fresh socket, no audio at all
    await s.wait_all(30)
    await s.utter("short_fr", load("short_fr"), m["short_fr"]["text"])
    s.begin("mid_fr+nonfinal", m["mid_fr"]["text"])
    pcm = load("mid_fr")
    await s.stream(pcm[: len(pcm) // 2])
    await s.commit(final=False)  # non-final mid-utterance
    await s.stream(pcm[len(pcm) // 2:] + silence(TAIL_MS))
    await s.commit()
    await s.utter("other_en", load("other_en"), m["other_en"]["text"])
    await s.commit()  # back-to-back final commit, no audio between
    await s.commit()  # and a third
    await s.wait_all(60)
    await asyncio.sleep(2)
    await s.close()
    r.finish()


async def q2(a):
    m, r = meta(), Run("q2_latency", a.url)
    for rep in range(a.reps):
        for k in ("short_fr", "mid_fr", "long_en"):
            s = await r.sock(f"{k}#{rep}")
            await s.utter(k, load(k), m[k]["text"])
            await s.wait_all(120)
            await s.close()
    r.finish()


async def q3(a):
    m, r = meta(), Run("q3_resend", a.url)
    u, ref = load("long_en"), m["long_en"]["text"]
    s = await r.sock("baseline")
    await s.utter("long_en", u, ref)
    await s.wait_all()
    await s.close()
    for variant, first, burst in (("same_burst", "long_en", True), ("same_rt", "long_en", False),
                                  ("other_burst", "mid_fr", True)):
        d = await r.sock(f"{variant}:dropped")
        d.begin("partial_5s")
        await d.stream(load(first)[: 5000 * 32])
        await d.abort()
        n = await r.sock(f"{variant}:new")
        await n.utter("long_en_full", u, ref, realtime=not burst)
        await n.wait_all()
        await n.close()
    r.finish()


async def stream_seq(s, items, gap_ms=300):
    m = meta()
    for k in items:
        await s.utter(k, load(k), m[k]["text"])
        await asyncio.sleep(gap_ms / 1000)  # the client sends nothing while gated
    await s.wait_all(180)


async def q4(a):
    r = Run("q4_concurrency", a.url)
    mic_items, sys_items, dict_items = ["pa0", "pa2", "pa4"], ["pb1", "pb3", "pb5"], ["dict_en", "dict_fr", "dict_en"]
    for phase, n in (("solo", 1), ("two", 2), ("three", 3)):
        socks = [await r.sock(f"{phase}:mic")]
        if n >= 2:
            socks.append(await r.sock(f"{phase}:sys"))
        if n >= 3:
            socks.append(await r.sock(f"{phase}:dict"))
        await asyncio.gather(*(stream_seq(s, it) for s, it in zip(socks, (mic_items, sys_items, dict_items))))
        for s in socks:
            await s.close()
    r.finish()


async def q5(a):
    m, r = meta(), Run("q5_silence", a.url)
    s = await r.sock("s")
    await s.utter("silence_20s", silence(20000), "", tail=False)
    await s.wait_all()
    await s.utter("noise_-50dBFS_20s", noise(20000), "", tail=False)
    await s.wait_all()
    await s.utter("mid_fr+10s_sil", load("mid_fr") + silence(10000), m["mid_fr"]["text"], tail=False)
    await s.wait_all()
    await s.close()
    r.finish()


async def q6(a):
    m, r = meta(), Run(f"q6_burst_{'load' if a.load else 'idle'}", a.url)
    s = await r.sock("burst")
    bg = None
    if a.load:
        mic = await r.sock("rt_mic")
        bg = asyncio.create_task(stream_seq(mic, ["pa0", "pa2", "pa4", "pa6"]))
        await asyncio.sleep(3)
    t = now()
    for k in ("part1_en", "part2_en"):
        await s.utter(k, load(k), m[k]["text"], realtime=False)
    sent = now()
    await s.wait_all(300)
    audio = sum(m[k]["sec"] + TAIL_MS / 1000 for k in ("part1_en", "part2_en"))
    if bg:
        await bg
    for x in r.socks:
        await x.close()
    r.finish({"burst_send_sec": round(sent - t, 2), "burst_total_sec": round(now() - t, 2),
              "audio_sec": round(audio, 2), "rtf": round((s.utts[-1]["t_done"] - t) / audio, 3)})


def rss(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) // 1024 if out else None


async def long_stream(s, prefix, order, until):
    m = meta()
    i = 0
    while time.monotonic() < until:
        k = f"{prefix}{order[i % len(order)]}"
        await s.utter(k, load(k), m[k]["text"])
        await asyncio.sleep(0.3)
        i += 1
    await s.wait_all(180)


async def q7(a):
    r = Run("q7_longrun", a.url)
    start = time.monotonic()
    until = start + a.minutes * 60
    mem = [{"min": 0, "rss_mb": rss(a.server_pid)}]

    async def sampler():
        while time.monotonic() < until:
            await asyncio.sleep(30)
            mem.append({"min": round((time.monotonic() - start) / 60, 1), "rss_mb": rss(a.server_pid)})
            r.log.write(json.dumps({"t": now(), "mem": mem[-1]}) + "\n")
            r.log.flush()

    s1, s2 = await r.sock("A"), await r.sock("B")
    n = len(PARAS)
    smp = asyncio.create_task(sampler())
    await asyncio.gather(long_stream(s1, "pa", list(range(n)), until),
                         long_stream(s2, "pb", list(range(n - 1, -1, -1)), until))
    smp.cancel()
    mem.append({"min": round((time.monotonic() - start) / 60, 1), "rss_mb": rss(a.server_pid)})
    windows = {}
    for s in (s1, s2):
        for u in s.utts:
            if not u["ref"]:
                continue
            w = windows.setdefault((s.name, int((u["t_commit"] - (start - T0)) // 180)), {"ref": "", "hyp": "", "c2d": []})
            w["ref"] += " " + u["ref"]
            w["hyp"] += " " + (u["text"] or "")
            if u["t_done"]:
                w["c2d"].append(u["t_done"] - u["t_commit"])
    per_window = [{"sock": k[0], "window_min": f"{k[1]*3}-{k[1]*3+3}", "wer": wer(v["ref"], v["hyp"]),
                   "utts": len(v["c2d"]), "c2d_mean": round(sum(v["c2d"]) / max(1, len(v["c2d"])), 3),
                   "c2d_max": round(max(v["c2d"], default=0), 3)} for k, v in sorted(windows.items())]
    for s in (s1, s2):
        await s.close()
    r.finish({"windows": per_window, "rss": mem})
    for w in per_window:
        print(w)
    print(mem)


# ---------- live client harness: corpus + scoring ----------

FR_S = ["Le jardinier", "La boulangère", "Le facteur", "La voisine", "Le maire", "La musicienne", "Le libraire", "La gardienne"]
FR_V = ["a repeint", "a déplacé", "a nettoyé", "a réparé", "a décoré", "a mesuré", "a rangé", "a photographié"]
FR_O = ["la vieille barrière", "le banc vert", "la fontaine ronde", "le kiosque à journaux", "la serre", "le portail", "la cabane", "le lavoir"]
FR_E = ["avant la pluie du soir", "pendant la fête du village", "sous un ciel gris", "avec beaucoup de patience",
        "sans prévenir personne", "au lever du soleil", "pour la rentrée des classes", "malgré le vent froid"]
EN_S = ["The baker", "The postman", "My neighbour", "The teacher", "The gardener", "The librarian", "The painter", "The mayor"]
EN_V = ["repaired", "painted", "cleaned", "moved", "measured", "decorated", "photographed", "tidied"]
EN_O = ["the wooden fence", "the green bench", "the round fountain", "the old greenhouse", "the garden gate", "the small cabin", "the bus shelter", "the stone wall"]
EN_E = ["before the evening rain", "during the village fair", "under a grey sky", "with a lot of patience",
        "without telling anyone", "at sunrise", "for the start of school", "despite the cold wind"]


def sentences(rnd, s, v, o, e, n, seen):
    out = []
    while len(out) < n:
        a = f"{rnd.choice(s)} {rnd.choice(v)} {rnd.choice(o)} {rnd.choice(e)}"
        b = f"{rnd.choice(s)} {rnd.choice(v)} {rnd.choice(o)} {rnd.choice(e)}"
        t = f"{a}, and then {b[0].lower()}{b[1:]}." if s is EN_S else f"{a}, puis {b[0].lower()}{b[1:]}."
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def cmd_timeline(a):
    """Two 16 kHz mono PCM16 timelines (mic, sys) of unique sentences + schedule."""
    out = AUDIO / a.name
    out.mkdir(parents=True, exist_ok=True)
    rnd, seen, sched = random.Random(11 if a.name == "live" else 23), set(), {}
    for src, voices in (("mic", (FR[0], EN[0])), ("sys", (EN[1], FR[1]))):
        pcm, items, i = bytearray(), [], 0
        while len(pcm) < a.seconds * RATE * 2:
            voice = voices[i % 2]
            fr = voice in FR
            text = sentences(rnd, FR_S if fr else EN_S, FR_V if fr else EN_V, FR_O if fr else EN_O,
                             FR_E if fr else EN_E, 1, seen)[0]
            name = f"{a.name}/{src}{i}"
            gen_one(name, voice, text)
            clip = load(name)
            (AUDIO / f"{name}.wav").unlink()
            start = len(pcm) / 2 / RATE
            pcm += clip
            items.append({"i": i, "text": text, "start": round(start, 2), "end": round(len(pcm) / 2 / RATE, 2)})
            pcm += silence(rnd.choice((2000, 2500, 3000)) if a.name == "live"
                           else rnd.choice((1500, 2000, 2500, 3000, 4000, 6000)))
            i += 1
        with wave.open(str(out / f"{src}.wav"), "wb") as w:
            w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
            w.writeframes(bytes(pcm))
        sched[src] = items
        print(src, len(items), "sentences", round(len(pcm) / 2 / RATE, 1), "s")
    (out / "schedule.json").write_text(json.dumps(sched, ensure_ascii=False, indent=1))


def cmd_score(a):
    """Score live-harness JSONL runs against the schedule (sentence match by text)."""
    sched = json.loads((AUDIO / a.audio / "schedule.json").read_text())
    rows = []
    for path in a.runs:
        ev = [json.loads(l) for l in open(path)]
        meta_ev = next(e for e in ev if e["ev"] == "start")
        end_s = meta_ev["seconds"]
        if a.window:
            for w0 in range(0, end_s, a.window):
                r = score_one(sched, ev, Path(path).stem + f"@{w0 // 60}-{(w0 + a.window) // 60}min",
                              lo=w0, hi=min(end_s, w0 + a.window), end_s=end_s)
                rows.append(r)
                print(json.dumps(r, ensure_ascii=False))
            continue
        res = score_one(sched, ev, Path(path).stem, 0, end_s, end_s)
        rows.append(res)
        print(json.dumps(res, ensure_ascii=False))
    if a.out:
        Path(a.out).write_text(json.dumps(rows, ensure_ascii=False, indent=1))


def score_one(sched, ev, name, lo, hi, end_s):
    """Scores sentences that start in [lo, hi[ and end before the feed ends."""
    res = {"run": name}
    if True:
        for src in ("mic", "sys"):
            ref = [s for s in sched[src] if s["end"] <= end_s and lo <= s["start"] < hi]
            if not ref:
                continue
            ids_in = {s["i"] for s in ref}
            span = (ref[0]["start"] - 1, ref[-1]["end"] + 1)
            dones = [e for e in ev if e["ev"] == "done" and e["src"] == src
                     and e.get("win_start_s") is not None and span[0] <= e["win_start_s"] <= span[1]] \
                if lo > 0 or hi < end_s else [e for e in ev if e["ev"] == "done" and e["src"] == src]
            matched, partial, unmatched = [], 0, []
            for d in dones:
                if not words(d["text"]):
                    continue
                if d.get("win_start_s") is not None:  # the client's own capture window
                    ws_, we_ = d["win_start_s"], d["win_end_s"]
                    best = max(ref, key=lambda s: min(s["end"], we_ + 0.1) - max(s["start"], ws_))
                else:
                    best = min(ref, key=lambda s: wer(s["text"], d["text"]))
                w_ = wer(best["text"], d["text"])
                if best["i"] not in ids_in:
                    continue
                if w_ <= 0.5:
                    matched.append((best["i"], w_, d))
                    partial += w_ > 0.2
                else:
                    unmatched.append(d["text"][:80])
            ids = [m[0] for m in matched]
            delays = [d["t"] - d["win_end_s"] for _, _, d in matched if d.get("win_end_s") is not None]
            gaps = [e for e in ev if e["ev"] == "gap" and e["src"] == src]
            missing = sorted(ids_in - set(ids))
            byi = {s["i"]: s for s in ref}
            uncovered = [i for i in missing if not any(
                g["start_s"] - 0.5 < byi[i]["end"] and byi[i]["start"] < g["end_s"] + 0.5 for g in gaps)]
            t_stop = next((e["t"] for e in ev if e["ev"] == "drained"), float("inf"))
            closes = [e["t"] for e in ev if e["ev"] == "closed_by_server" and e["src"] == src and e["t"] < t_stop]
            seen = [e["t"] for e in ev if e["ev"] == "ws_onclosed" and e["src"] == src]
            close_lat = [round(min((x for x in seen if x >= c - 0.05), default=float("nan")) - c, 3) for c in closes]
            buf = [e[src] for e in ev if e["ev"] == "buffered" and lo <= e["t"] < hi]
            res[src] = {
                "ref_words": sum(len(words(s["text"])) for s in ref),
                "got_words": sum(len(words(d["text"])) for d in dones),
                "wer_all": wer(" ".join(s["text"] for s in ref), " ".join(d["text"] for d in dones)),
                "sentences": len(ref), "dup": len(ids) - len(set(ids)),
                "missing": missing, "missing_outside_gaps": uncovered,
                "server_closes": len(closes), "close_to_onclosed_s": close_lat,
                "partial": partial, "unmatched": unmatched,
                "in_order": ids == sorted(ids),
                "gaps": [(round(g["start_s"], 1), round(g["end_s"] - g["start_s"], 1)) for g in gaps],
                "connects": sum(1 for e in ev if e["ev"] == "connect" and e["src"] == src),
                "control": [e["type"] for e in ev if e["ev"] == "control" and e["src"] == src],
                "max_buffered_s": max(buf, default=0),
                "max_delay_s": round(max(delays, default=0), 1),
                "last_done_after_end_s": round(max((d["t"] for d in dones), default=0) - end_s, 1),
            }
        res["footprint_mb"] = [(round(e["t"] / 60, 1), e["mb"]) for e in ev
                               if e["ev"] == "footprint" and lo <= e["t"] < hi + 1]
        res["drained"] = next((e for e in ev if e["ev"] == "drained"), None) if hi >= end_s else None
    return res


def grams(ws, n):
    from collections import Counter
    return Counter(tuple(ws[i:i + n]) for i in range(len(ws) - n + 1))


def cmd_svcscore(a):
    """Scores a service_probe run from its final segment dump (one session)."""
    ev = [json.loads(l) for l in open(a.run)]
    sched = json.loads((AUDIO / a.audio / "schedule.json").read_text())
    segs = [e for e in ev if e["ev"] == "segments"][-1]["list"]
    sess = a.session or next(e["session"] for e in ev if e["ev"] == "meeting_started")
    feed = next(e for e in ev if e["ev"] == "feed_start")
    end_s = int(feed["seconds"])
    seen = {}  # first wall time each final (non-partial, non-marker) id appeared
    for e in ev:
        if e["ev"] == "segment" and e["session"] == sess and not e.get("partial") and e["id"] not in seen \
                and not e["text"].startswith("Transcription interrompue"):
            seen[e["id"]] = (e["t"], e["ts"])
    out = {"run": Path(a.run).stem, "windows": []}
    for src in ("mic", "sys"):
        ref = [s for s in sched[src] if s["end"] <= end_s]
        mine = sorted((g for g in segs if g["session"] == sess and g["src"] == src), key=lambda g: g["t"])
        markers = [g for g in mine if g["text"].startswith("Transcription interrompue")]
        live = [g for g in mine if g not in markers]
        hyp_all = words(" ".join(g["text"] for g in live))
        hg = grams(hyp_all, 3)
        missing = [s["i"] for s in ref if (lambda g: sum(min(c, hg[k]) for k, c in g.items()) / max(1, sum(g.values())))(grams(words(s["text"]), 3)) < 0.5]
        rg4, hg4 = grams(words(" ".join(s["text"] for s in ref)), 4), grams(hyp_all, 4)
        dup4 = sum(max(0, c - rg4[k]) for k, c in hg4.items() if rg4[k] > 0)
        delays = []
        for g in live:
            if g["id"] in seen and "_backfill_" not in g["id"]:
                t_wall, ts = seen[g["id"]]
                s = min(ref, key=lambda s: abs(s["start"] - ts), default=None)
                if s:
                    delays.append(round(t_wall - feed["t"] - s["end"], 1))
        out[src] = {"sentences": len(ref), "wer": wer(" ".join(s["text"] for s in ref), " ".join(hyp_all)),
                    "missing": missing, "dup_4grams": dup4, "markers_left": [m["text"] for m in markers],
                    "partial_left": sum(1 for g in live if g.get("partial")),
                    "backfill_segments": sum(1 for g in live if "_backfill_" in g["id"]),
                    "max_delay_s": max(delays, default=None)}
        if a.window:
            for w0 in range(0, end_s, a.window):
                r = [s for s in ref if w0 <= s["start"] < w0 + a.window]
                h = [g for g in live if w0 <= g["t"] < w0 + a.window]
                hw = words(" ".join(g["text"] for g in h))
                d = [x for g, x in zip([g for g in live if g["id"] in seen and "_backfill_" not in g["id"]], delays)
                     if w0 <= g["t"] < w0 + a.window]
                out["windows"].append({"src": src, "min": f"{w0 // 60}-{(w0 + a.window) // 60}",
                                       "wer": wer(" ".join(s["text"] for s in r), " ".join(hw)),
                                       "missing": [i for i in missing if any(s["i"] == i for s in r)],
                                       "max_delay_s": max(d, default=None)})
    print(json.dumps(out, ensure_ascii=False, indent=1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", default="ws://127.0.0.1:8017/v1/realtime")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("gen")
    for q in ("q1", "q3", "q4", "q5"):
        sub.add_parser(q)
    sub.add_parser("q2").add_argument("--reps", type=int, default=2)
    sub.add_parser("q6").add_argument("--load", action="store_true")
    q7p = sub.add_parser("q7")
    q7p.add_argument("--minutes", type=float, default=15)
    q7p.add_argument("--server-pid", type=int, required=True)
    tl = sub.add_parser("timeline")
    tl.add_argument("--seconds", type=int, default=300)
    tl.add_argument("--name", default="live")
    sc = sub.add_parser("score")
    sc.add_argument("runs", nargs="+")
    sc.add_argument("--out")
    sc.add_argument("--audio", default="live")
    sc.add_argument("--window", type=int, default=0)
    ss = sub.add_parser("svcscore")
    ss.add_argument("run")
    ss.add_argument("--audio", default="live")
    ss.add_argument("--session")
    ss.add_argument("--window", type=int, default=0)
    a = p.parse_args()
    if a.cmd in ("gen", "timeline", "score", "svcscore"):
        return globals()[f"cmd_{a.cmd}"](a)
    asyncio.run(globals()[a.cmd](a))


if __name__ == "__main__":
    assert wer("Le chat, noir.", "le chat noir") == 0 and wer("a b c d", "a x c") == 0.5
    sys.exit(main())
