"""floormaps.py -- a page of every floor's map with the deathmatch items on
it (DMITEMS.md): the main floor the weapon pass uses, the parts it leaves
(secrets, closets), and each gun and clip -- id's own, a clip of id's made a
gun, or one the pass added.  Recorded fresh through the real server and game
(--dmitems off and on, four slots), read with the Win32 replay's W3DDMI hook.
StevenC & Claude (Anthropic), 2026-11-11.

    python tests/floormaps.py            -> stage/dmi/floormaps.html

The page draws id's own maps, so it stays here (stage/ is git-ignored) and
is not published: open it in a browser.
"""
import concurrent.futures
import json
import os
import queue
import re
import struct
import subprocess
import sys
import time

ROOT = r"C:\wolf3d"
OUT = os.path.join(ROOT, "stage", "dmi", "maps")
os.makedirs(OUT, exist_ok=True)
GAMES = [("wl6", "WL6", os.path.join(ROOT, "win32", "run"), "W3DREP.EXE", 60),
         ("sod", "SOD", os.path.join(ROOT, "SOD"), "W3DREPS.EXE", 21)]
PORTS = queue.Queue()
for k in range(4):
    PORTS.put(32300 + 4 * k)


def carmack(src, nwords):
    out, i = [], 0
    while len(out) < nwords:
        w = src[i] | src[i + 1] << 8
        i += 2
        hi, count = w >> 8, w & 0xff
        if hi in (0xA7, 0xA8):
            if count == 0:
                out.append((hi << 8) | src[i])
                i += 1
            elif hi == 0xA7:
                off = src[i]
                i += 1
                start = len(out) - off
                out.extend(out[start + k] for k in range(count))
            else:
                off = src[i] | src[i + 1] << 8
                i += 2
                out.extend(out[off + k] for k in range(count))
        else:
            out.append(w)
    return out


def rlew(words, tag):
    out, i, n = [], 1, words[0] // 2
    while len(out) < n:
        w = words[i]
        i += 1
        if w == tag:
            out.extend([words[i + 1]] * words[i])
            i += 2
        else:
            out.append(w)
    return out


def blockers(sod):
    src = open(os.path.join(ROOT, "WOLFSRC", "WL_ACT1.C"), errors="replace").read()
    table = src[src.index("statinfo[] ="):src.index("{-1}")]
    if sod:
        table = re.sub(r"#ifndef SPEAR.*?#else(.*?)#endif", r"\1", table, flags=re.S)
    else:
        table = re.sub(r"#ifndef SPEAR(.*?)#else.*?#endif", r"\1", table, flags=re.S)
    entries = re.findall(r"\{SPR_STAT_\d+[^}]*\}", table)
    return {i + 23 for i, e in enumerate(entries) if ",block" in e.replace(" ", "")}


def planes(run, ext, m):
    mh = open(os.path.join(run, "MAPHEAD." + ext), "rb").read()
    gm = open(os.path.join(run, "GAMEMAPS." + ext), "rb").read()
    tag = struct.unpack_from("<H", mh, 0)[0]
    hdr = struct.unpack_from("<100l", mh, 2)[m]
    ps = struct.unpack_from("<3l", gm, hdr)
    pl = struct.unpack_from("<3H", gm, hdr + 12)
    name = gm[hdr + 22:hdr + 38].split(b"\0")[0].decode("latin-1")
    p = []
    for k in range(2):
        raw = gm[ps[k]:ps[k] + pl[k]]
        p.append(rlew(carmack(raw[2:], (raw[0] | raw[1] << 8) // 2), tag))
    return name, p[0], p[1]


def grid(p0, p1, block):
    """a char a tile: # wall, D door, P pushwall, b blocking static, . open"""
    g = []
    for y in range(64):
        for x in range(64):
            t0, t1 = p0[y * 64 + x], p1[y * 64 + x]
            if t1 == 98:
                g.append("P")
            elif 90 <= t0 <= 101:
                g.append("D")
            elif t0 < 106:
                g.append("#")
            elif t1 in block:
                g.append("b")
            else:
                g.append(".")
    return g


def main_floor(g, p1):
    tiles = [(x, y) for x in range(1, 63) for y in range(1, 63) if g[y * 64 + x] in ".D"]
    left, best = set(tiles), set()
    start = next((i % 64, i // 64) for i, t in enumerate(p1) if 19 <= t <= 22)
    for s in [start] + tiles:
        if s not in left or len(best) * 2 >= len(tiles):
            continue
        reg, st = {s}, [s]
        left.discard(s)
        while st:
            x, y = st.pop()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in left:
                    left.discard(n)
                    reg.add(n)
                    st.append(n)
        if len(reg) > len(best):
            best = reg
    return best


def record(m, items, port):
    path = os.path.join(OUT, "F%02d%s.MPR" % (m, "I" if items else "N"))
    if os.path.exists(path):
        os.remove(path)
    srv = subprocess.Popen([sys.executable, os.path.join(ROOT, "mp", "mpserver.py"), "--port", str(port),
                            "--control", str(port + 1000), "--players", "4", "--bots", "3", "--mode", "dm",
                            "--map", str(m), "--steps", "20", "--once", "--record", path, "--quiet",
                            "--dmitems", "on" if items else "off"],
                           cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    subprocess.run([sys.executable, os.path.join(ROOT, "mp", "mpfake.py"), "--port", str(port), "--fps", "35",
                    "--load", "1"], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    srv.wait(30)
    return path


def statics(mpr, run, rep, port):
    local = os.path.join(run, "FM%d.MPR" % port)
    with open(mpr, "rb") as f, open(local, "wb") as g:
        g.write(f.read())
    out = subprocess.run([os.path.join(ROOT, "win32", rep), "REPLAY", os.path.basename(local), "FAST", "NOAL"], cwd=run,
                         capture_output=True, text=True, errors="replace", env=dict(os.environ, W3DDMI="1")).stdout
    os.remove(local)
    return {int(a): (int(b), int(c), int(d)) for a, b, c, d in re.findall(r"^dmi st(\d+) (-?\d+) at (\d+),(\d+)",
                                                                       out, re.M)}


def one(job):
    game, ext, run, rep, m = job
    port = PORTS.get()
    try:
        off = statics(record(m, False, port), run, rep, port)
        on = statics(record(m, True, port), run, rep, port)
    finally:
        PORTS.put(port)
    kinds = {28: "clip", 29: "mg", 30: "cg"}
    if game == "sod":
        kinds[51] = "clip"
    items = []
    for slot, (shape, x, y) in on.items():
        k = kinds.get(shape)
        if not k:
            continue
        was = off.get(slot)
        how = "id" if was == (shape, x, y) else "made" if was and was[1:] == (x, y) else "added"
        items.append([k, how, x, y])
    return game, m, items


jobs = [(g, e, r, rep, m) for g, e, r, rep, n in GAMES for m in range(n)]
floors = []
with concurrent.futures.ThreadPoolExecutor(4) as ex:
    for game, m, items in ex.map(one, jobs):
        g, e, r, rep, n = next(x for x in GAMES if x[0] == game)
        name, p0, p1 = planes(r, e, m)
        gr = grid(p0, p1, blockers(game == "sod"))
        fl = main_floor(gr, p1)
        for (x, y) in fl:
            if gr[y * 64 + x] == ".":
                gr[y * 64 + x] = "+"
        label = ("E%dL%d" % (m // 10 + 1, m % 10 + 1)) if game == "wl6" else "Spear floor %d" % (m + 1)
        floors.append({"game": game, "map": m, "label": label, "name": name, "grid": "".join(gr), "items": items})
        print(label, len(items), "items", flush=True)

html = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Deathmatch Floors</title>
<style>
:root { --bg:#f6f5f2; --fg:#1c1c1c; --muted:#666; --card:#fff; --line:#ddd; }
@media (prefers-color-scheme: dark) { :root { --bg:#151515; --fg:#eee; --muted:#999; --card:#1f1f1f; --line:#333; } }
body { margin:0; padding:16px; background:var(--bg); color:var(--fg); font:14px/1.4 system-ui, sans-serif; }
h1 { font-size:20px; margin:0 0 4px; } p { margin:4px 0 12px; color:var(--muted); }
.legend span { display:inline-block; margin-right:14px; } .sw { display:inline-block; width:12px; height:12px; vertical-align:-2px; margin-right:4px; border-radius:2px; }
.grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(280px, 1fr)); gap:12px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:8px; }
.card h2 { font-size:14px; margin:0 0 6px; } .card small { color:var(--muted); }
canvas { width:100%; height:auto; image-rendering:pixelated; display:block; border-radius:4px; }
select { margin:0 0 12px; padding:4px 6px; }
</style></head><body>
<h1>Deathmatch floors</h1>
<p>Every floor as the weapon pass sees it (DMITEMS.md): the main floor it plays on, what it leaves out, and every gun and clip. Four slots: two machine guns wanted.</p>
<div class="legend">
<span><i class="sw" style="background:#e9e4d6"></i>main floor</span>
<span><i class="sw" style="background:#9a958c"></i>open, not the main floor (secrets, closets)</span>
<span><i class="sw" style="background:#3a3a3a"></i>wall</span>
<span><i class="sw" style="background:#2f7d4f"></i>pushwall</span>
<span><i class="sw" style="background:#b0712b"></i>door</span>
<span><i class="sw" style="background:#2563eb"></i>machine gun</span>
<span><i class="sw" style="background:#dc2626"></i>chaingun</span>
<span><i class="sw" style="background:#d4a017"></i>clip</span>
<span>&#9679; id's own &nbsp; &#9675; a clip of id's made this &nbsp; &#9670; added</span>
</div>
<p><select id="game"><option value="wl6">Wolfenstein 3-D</option><option value="sod">Spear of Destiny</option></select></p>
<div class="grid" id="grid"></div>
<script>
const FLOORS = __DATA__;
const COL = {"#":"#3a3a3a","D":"#b0712b","P":"#2f7d4f","b":"#6b665e",".":"#9a958c","+":"#e9e4d6"};
const ITEM = {mg:"#2563eb", cg:"#dc2626", clip:"#d4a017"};
function draw(game) {
  const g = document.getElementById("grid"); g.innerHTML = "";
  for (const f of FLOORS.filter(f => f.game === game)) {
    const card = document.createElement("div"); card.className = "card";
    const n = c => f.items.filter(i => i[0] === c).length;
    card.innerHTML = `<h2>${f.label} <small>${f.name}</small></h2><small>${n("mg")} MG, ${n("cg")} CG, ${n("clip")} clips</small>`;
    const cv = document.createElement("canvas"); const S = 8; cv.width = cv.height = 64 * S;
    const c = cv.getContext("2d");
    for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) { c.fillStyle = COL[f.grid[y * 64 + x]] || "#000"; c.fillRect(x * S, y * S, S, S); }
    for (const [k, how, x, y] of f.items) {
      const cx = x * S + S / 2, cy = y * S + S / 2; c.fillStyle = c.strokeStyle = ITEM[k]; c.lineWidth = 2; c.beginPath();
      if (how === "added") { c.moveTo(cx, cy - 6); c.lineTo(cx + 6, cy); c.lineTo(cx, cy + 6); c.lineTo(cx - 6, cy); c.closePath(); c.fill(); }
      else { c.arc(cx, cy, k === "clip" ? 3 : 5, 0, 7); how === "id" ? c.fill() : c.stroke(); }
    }
    card.appendChild(cv); g.appendChild(card);
  }
}
const sel = document.getElementById("game"); sel.onchange = () => draw(sel.value); draw("wl6");
</script></body></html>"""
floors.sort(key=lambda f: (f["game"] != "wl6", f["map"]))
open(os.path.join(ROOT, "stage", "dmi", "floormaps.html"), "w", encoding="utf-8").write(
    html.replace("__DATA__", json.dumps(floors)))
print("wrote stage/dmi/floormaps.html")
