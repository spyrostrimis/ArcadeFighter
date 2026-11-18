"""Move tracker page: docs/moves/index.html (open it in a browser).

    python tools/moves_page.py           # rebuild docs/moves/data.js from the project
    python tools/moves_page.py --serve   # rebuild, then serve on http://127.0.0.1:8765
                                         # (notes and status become editable in the page)

What is done comes from the project itself, so the page can't go stale:
  - the move list and frame data from scripts/sim/char_data.gd,
  - "has sprites" from the exported sprite sets (assets/fighters/<set>/<set>.json),
  - the thumbnail from assets/fighters/<set>/preview_<move>.gif,
  - sheet links from art/<char>/ref/<move>* and art/<char>/keys/<move>_*.
Only the hand-written part lives in docs/moves/notes.json: a note, a status override
(wip / redo / skip) and extra sheet links for moves whose files have older names.
"""
import json
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from functools import partial

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE_DIR = os.path.join(ROOT, "docs", "moves")
NOTES = os.path.join(PAGE_DIR, "notes.json")
DATA = os.path.join(PAGE_DIR, "data.js")
PORT = 8765

# Characters alphabetically. "set" is the sprite set the fight uses.
CHARS = [
    {"id": "ced", "name": "CED", "set": "ced", "art": "ced"},
    {"id": "kros", "name": "KROS", "set": "kros_nocape", "art": "kros", "extra_sets": ["kros"]},
    {"id": "murfurrie", "name": "MURFURRIE", "set": "murfurrie", "art": "murfurrie"},
]

BTN = {  # suffix -> (name, key, strength, kind)
    "lp": ("Light Punch", "A", "L", "punch"),
    "mp": ("Medium Punch", "S", "M", "punch"),
    "hp": ("Heavy Punch", "D", "H", "punch"),
    "lk": ("Light Kick", "Z", "L", "kick"),
    "mk": ("Medium Kick", "X", "M", "kick"),
    "hk": ("Heavy Kick", "C", "H", "kick"),
}
STANCE = {"st": ("Standing", []), "cr": ("Crouching", ["down"]), "j": ("Jumping", ["up"])}
EXTRA_NAMES = {"cr_hp": "anti-air uppercut", "cr_lk": "low", "cr_mk": "low", "cr_hk": "sweep"}

BASICS = [
    ("idle", "Idle (fighting stance)", []),
    ("walk_f", "Walk forward", ["fwd"]),
    ("walk_b", "Walk back", ["back"]),
    ("crouch", "Crouch", ["down"]),
    ("jump", "Jump", ["up"]),
]
REACTIONS = [
    ("block", "Block", ["back"]),
    ("cr_block", "Crouch block", ["downback"]),
    ("hit_high", "Hit (high)", []),
    ("hit_low", "Hit (low)", []),
    ("knockdown", "Knockdown", []),
    ("getup", "Get up", []),
    ("ko", "KO", []),
    ("win", "Win pose", []),
    ("lose", "Lose", []),
]
MOTIONS = {"qcf": ["down", "downfwd", "fwd"], "qcb": ["down", "downback", "back"],
           "dp": ["fwd", "down", "downfwd"]}


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def parse_char_data():
    text = open(os.path.join(ROOT, "scripts", "sim", "char_data.gd"), encoding="utf-8").read()
    out = {}
    for c in CHARS:
        m = re.search(r"static func _%s\(\).*?(?=\nstatic func |\Z)" % c["id"], text, re.S)
        sec = m.group(0) if m else ""
        moves = {}
        for mm in re.finditer(r'"(\w+)":\s*_mv\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)', sec):
            name = mm.group(1)
            if name not in moves:
                moves[name] = [int(x) for x in mm.group(2, 3, 4, 5)]
        specials = []
        for sm in re.finditer(r'"motion":\s*"(\w+)",\s*"buttons":\s*\[([\d,\s]+)\],\s*"move":\s*"(\w+)"', sec):
            btns = [int(b) for b in sm.group(2).split(",")]
            specials.append({"motion": sm.group(1), "buttons": btns, "move": sm.group(3)})
        out[c["id"]] = (moves, specials)
    return out


def sprite_anims(set_name):
    p = os.path.join(ROOT, "assets", "fighters", set_name, set_name + ".json")
    if not os.path.exists(p):
        return []
    return list(json.load(open(p, encoding="utf-8")).get("animations", {}))


def find_files(art, move):
    links = []
    for sub in ("ref", "keys"):
        d = os.path.join(ROOT, "art", art, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            stem = os.path.splitext(f)[0]
            if stem == move or stem.startswith(move + "_"):
                if "photo" in f:
                    continue
                if re.fullmatch(re.escape(move) + r"_\d+[a-z]?\.png", f):
                    continue  # single key poses: the preview covers them
                links.append(rel(os.path.join(d, f)))
    return links


def label_for(path):
    f = os.path.basename(path)
    if "/ref/" in path:
        return ("Split sheet" if "split" in f else "ChatGPT sheet") + " · " + f
    if f.endswith("_ingame.gif"):
        return "In-game GIF"
    if f.endswith("_preview.png"):
        return "Cut-out keys"
    return f


def build():
    notes = json.load(open(NOTES, encoding="utf-8")) if os.path.exists(NOTES) else {}
    data = parse_char_data()
    chars = []
    for c in CHARS:
        moves_fd, specials = data[c["id"]]
        have = sprite_anims(c["set"])
        extra_have = {s: sprite_anims(s) for s in c.get("extra_sets", [])}
        groups = []

        def item(mid, name, inp, key=None, strength=None, kind=None, fd=None):
            n = notes.get(f"{c['id']}/{mid}", {})
            done = mid in have
            gif = os.path.join(ROOT, "assets", "fighters", c["set"], f"preview_{mid}.gif")
            files = find_files(c["art"], mid)
            for extra in n.get("sheets", []):
                if extra not in files:
                    files.append(extra)
            return {
                "id": mid, "name": name, "input": inp, "key": key, "strength": strength,
                "kind": kind, "fd": fd, "done": done,
                "status": n.get("status", ""), "note": n.get("note", ""),
                "thumb": rel(gif) if done and os.path.exists(gif) else "",
                "links": [{"href": f, "label": label_for(f)} for f in files],
            }

        groups.append({"name": "Basics", "items": [item(m, n, i) for m, n, i in BASICS]})
        for st, (sname, dirs) in STANCE.items():
            items = []
            for suf, (bname, key, strength, kind) in BTN.items():
                mid = f"{st}_{suf}"
                name = f"{sname} {bname}"
                if mid in EXTRA_NAMES:
                    name += f" ({EXTRA_NAMES[mid]})"
                items.append(item(mid, name, dirs, key, strength, kind, moves_fd.get(mid)))
            groups.append({"name": sname, "items": items})
        sp_items = []
        for sp in specials:
            mid = sp["move"]
            kind = "punch" if all(b < 3 for b in sp["buttons"]) else "kick"
            keys = "/".join(BTN[["lp", "mp", "hp", "lk", "mk", "hk"][b]][1] for b in sorted(sp["buttons"]))
            name = mid.replace("_", " ").title()
            sp_items.append(item(mid, name, MOTIONS.get(sp["motion"], [sp["motion"]]), keys, "any", kind,
                                 moves_fd.get(mid)))
        groups.append({"name": "Specials", "items": sp_items})
        groups.append({"name": "Reactions", "items": [item(m, n, i) for m, n, i in REACTIONS]})
        listed = {it["id"] for g in groups for it in g["items"]}
        extras = []
        for s, anims in extra_have.items():
            for a in anims:
                n = notes.get(f"{c['id']}/{s}:{a}", {})
                gif = os.path.join(ROOT, "assets", "fighters", s, f"preview_{a}.gif")
                files = find_files(c["art"], a) + [x for x in n.get("sheets", [])]
                extras.append({
                    "id": f"{s}:{a}", "name": n.get("name", f"{a} ({s} costume)"), "input": [],
                    "key": None, "strength": None, "kind": None, "fd": None, "done": True,
                    "status": n.get("status", ""), "note": n.get("note", ""),
                    "thumb": rel(gif) if os.path.exists(gif) else "",
                    "links": [{"href": f, "label": label_for(f)} for f in dict.fromkeys(files)],
                })
        for a in have:
            if a not in listed:
                extras.append(item(a, a, []))
        if extras:
            groups.append({"name": "Extras", "items": extras})
        chars.append({"id": c["id"], "name": c["name"], "groups": groups})

    os.makedirs(PAGE_DIR, exist_ok=True)
    with open(DATA, "w", encoding="utf-8", newline="\n") as f:
        f.write("// Generated by tools/moves_page.py: don't edit (notes go in notes.json).\n")
        f.write("window.MOVES = " + json.dumps({"chars": chars}, indent=1) + ";\n")
    total = sum(len(g["items"]) for c in chars for g in c["groups"])
    done = sum(it["done"] for c in chars for g in c["groups"] for it in g["items"])
    print(f"wrote {rel(DATA)}: {done}/{total} animations have sprites")


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        if self.path != "/api/note":
            self.send_error(404)
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        key = str(body.get("key", ""))
        if not re.fullmatch(r"[a-z]+/[a-z_:]+", key):
            self.send_error(400)
            return
        notes = json.load(open(NOTES, encoding="utf-8")) if os.path.exists(NOTES) else {}
        entry = notes.get(key, {})
        for field in ("note", "status"):
            val = str(body.get(field, "")).strip()
            if val:
                entry[field] = val
            else:
                entry.pop(field, None)
        if entry:
            notes[key] = entry
        else:
            notes.pop(key, None)
        with open(NOTES, "w", encoding="utf-8", newline="\n") as f:
            json.dump(dict(sorted(notes.items())), f, indent=2, ensure_ascii=False)
            f.write("\n")
        build()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok": true}')


if __name__ == "__main__":
    build()
    if "--serve" in sys.argv:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), partial(Handler, directory=ROOT))
        print(f"move tracker: http://127.0.0.1:{PORT}/docs/moves/  (Ctrl+C to stop)")
        srv.serve_forever()
