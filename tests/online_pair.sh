#!/usr/bin/env bash
# Real online check: two game windows on this PC create and join a room through
# the public signalling brokers, connect over WebRTC and play scripted matches
# (CPU-driven inputs through the normal online path, rollback on).
# Usage: tests/online_pair.sh [OUT_DIR] [MATCHES] [NETSIM]
#   NETSIM = "LAG,JITTER,LOSS%" added to each side's outgoing game packets,
#            e.g. 40,15,5 (default) to force real rollbacks on a local link.
# Env: GODOT (executable; an exported game .exe works too, with GODOT_ARGS=""),
#      GODOT_ARGS (default "--path ."), HOST_EXTRA (e.g. --reselect).
# Exit code 0 when both sides finished every match with matching checksums.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-C:/Godot/Godot_v4.7.2-stable_win64.exe}"
GODOT_ARGS="${GODOT_ARGS---path .}"
HOST_EXTRA="${HOST_EXTRA:-}"
OUT="${1:-${TMPDIR:-/tmp}/af_online}"
MATCHES="${2:-2}"
NETSIM="${3:-40,15,5}"
rm -rf "$OUT"; mkdir -p "$OUT"
COMMON=(--autoplay --matches="$MATCHES" --quit_after=$((MATCHES * 420 + 120)) --netsim="$NETSIM" --cpu=2)

"$GODOT" $GODOT_ARGS --resolution 768x432 --position 0,40 -- --host $HOST_EXTRA --codefile="$OUT/code.txt" \
	--autopick=ced --result="$OUT/host.jsonl" --netlog="$OUT/host.log" \
	--shot="$OUT/host" --shot_at=200,1500,9500 "${COMMON[@]}" > "$OUT/host.out" 2>&1 &
HOST=$!
"$GODOT" $GODOT_ARGS --resolution 768x432 --position 780,40 -- --join=@"$OUT/code.txt" \
	--autopick=kros --result="$OUT/guest.jsonl" --netlog="$OUT/guest.log" \
	--shot="$OUT/guest" --shot_at=200,1500,9500 "${COMMON[@]}" > "$OUT/guest.out" 2>&1 &
GUEST=$!
wait $HOST; HC=$?
wait $GUEST; GC=$?
echo "exit codes: host $HC guest $GC   room $(cat "$OUT/code.txt" 2>/dev/null)"
echo "--- host";  cat "$OUT/host.jsonl" 2>/dev/null
echo "--- guest"; cat "$OUT/guest.jsonl" 2>/dev/null
python - "$OUT" "$MATCHES" <<'PY'
import json, sys
out, n = sys.argv[1], int(sys.argv[2])
def load(p):
    try:
        rows = [json.loads(l) for l in open(p) if l.strip()]
    except OSError:
        return []
    for r in rows:
        if "error" in r or "lost" in r:
            print(p.rsplit("/", 1)[-1], "reported:", r)
    return [r for r in rows if "match" in r]
h, g = load(out + "/host.jsonl"), load(out + "/guest.jsonl")
ok = len(h) == n and len(g) == n
for a, b in zip(h, g):
    common = set(a.get("checks", {})) & set(b.get("checks", {}))
    same = all(a["checks"][k] == b["checks"][k] for k in common)
    good = (a.get("desync", 0) < 0 and b.get("desync", 0) < 0 and a["winner"] == b["winner"]
            and same and len(common) > 0 and a["checks_matched"] > 0)
    print("match %s: %s vs %s winner %s  checks matched %d/%d  common tail checksums %d %s  rollbacks %d/%d (max %d/%d)  rtt %d/%d ms" % (
        a["match"], a["p1"], a["p2"], a["winner"], a["checks_matched"], b["checks_matched"],
        len(common), "equal" if same else "DIFFER", a["rollbacks"], b["rollbacks"], a["max_depth"], b["max_depth"],
        a["rtt_ms"], b["rtt_ms"]))
    ok = ok and good
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
